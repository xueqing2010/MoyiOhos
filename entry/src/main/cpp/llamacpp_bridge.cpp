// MoyiOhos llama.cpp NAPI bridge (T041 / plan D11).
// Exposes: getVersion / loadModel / generate(streaming via
// napi_threadsafe_function) / stopGeneration / unloadModel.
//
// Generation runs on a worker std::thread; each decoded token is
// marshalled back to the ArkTS thread through a threadsafe function
// (逐 token 回调). A handle is returned by loadModel and used by the
// other calls.

#include <napi/native_api.h>

#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "llama.h"

namespace {

struct ModelEntry {
    llama_model * model = nullptr;
    llama_context * ctx = nullptr;
    std::atomic<bool> stop{false};
    std::atomic<bool> busy{false};
};

std::mutex g_mutex;
std::unordered_map<int, ModelEntry *> g_entries;
int g_next_handle = 1;

struct GenCallbacks {
    napi_ref on_token = nullptr;
    napi_ref on_done = nullptr;
};

struct GenMsg {
    bool done = false;
    bool is_error = false;
    std::string text;
};

void finalize_callbacks(napi_env env, void * data, void * hint) {
    GenCallbacks * cbs = static_cast<GenCallbacks *>(data);
    if (cbs == nullptr) {
        return;
    }
    if (cbs->on_token != nullptr) {
        napi_delete_reference(env, cbs->on_token);
    }
    if (cbs->on_done != nullptr) {
        napi_delete_reference(env, cbs->on_done);
    }
    delete cbs;
}

void call_js(napi_env env, napi_value js_cb, void * context, void * data) {
    GenCallbacks * cbs = static_cast<GenCallbacks *>(context);
    GenMsg * msg = static_cast<GenMsg *>(data);
    if (cbs == nullptr || msg == nullptr) {
        delete msg;
        return;
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value fn = nullptr;
    if (msg->done) {
        if (cbs->on_done != nullptr) {
            napi_get_reference_value(env, cbs->on_done, &fn);
        }
    } else {
        if (cbs->on_token != nullptr) {
            napi_get_reference_value(env, cbs->on_token, &fn);
        }
    }
    if (fn != nullptr) {
        napi_value arg = nullptr;
        napi_create_string_utf8(env, msg->text.c_str(), msg->text.size(), &arg);
        if (msg->done) {
            napi_value errArg = nullptr;
            napi_get_boolean(env, msg->is_error, &errArg);
            napi_value args[2] = {arg, errArg};
            napi_call_function(env, undefined, fn, 2, args, nullptr);
        } else {
            napi_call_function(env, undefined, fn, 1, &arg, nullptr);
        }
    }
    delete msg;
}

void run_generation(napi_env env, napi_threadsafe_function tsfn, ModelEntry * entry,
                    std::string prompt, int maxTokens, float temperature) {
    bool error = false;
    std::string error_text;
    const llama_vocab * vocab = llama_model_get_vocab(entry->model);

    std::vector<llama_token> tokens(prompt.size() + 8);
    int n = llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                           tokens.data(), static_cast<int32_t>(tokens.size()), true, true);
    if (n < 0) {
        tokens.resize(-n);
        n = llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                           tokens.data(), static_cast<int32_t>(tokens.size()), true, true);
    }
    if (n <= 0) {
        GenMsg * msg = new GenMsg();
        msg->done = true;
        msg->is_error = true;
        msg->text = "提示词分词失败";
        napi_call_threadsafe_function(tsfn, msg, napi_tsfn_blocking);
        napi_release_threadsafe_function(tsfn, napi_tsfn_release);
        return;
    }

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    const int n_batch = 512;
    for (int i = 0; i < n; i += n_batch) {
        int count = (n - i) < n_batch ? (n - i) : n_batch;
        llama_batch batch = llama_batch_get_one(tokens.data() + i, count);
        if (llama_decode(entry->ctx, batch) != 0) {
            error = true;
            error_text = "提示词解码失败（模型或上下文不兼容）";
            break;
        }
    }

    std::string full;
    char buf[256];
    if (!error) {
        for (int produced = 0; produced < maxTokens; produced++) {
            if (entry->stop.load()) {
                break;
            }
            llama_token id = llama_sampler_sample(smpl, entry->ctx, -1);
            if (llama_vocab_is_eog(vocab, id)) {
                break;
            }
            int piece_len = llama_token_to_piece(vocab, id, buf, sizeof(buf), 0, false);
            if (piece_len > 0) {
                std::string piece(buf, piece_len);
                full += piece;
                GenMsg * msg = new GenMsg();
                msg->text = piece;
                napi_call_threadsafe_function(tsfn, msg, napi_tsfn_blocking);
            }
            llama_sampler_accept(smpl, id);
            llama_batch batch = llama_batch_get_one(&id, 1);
            if (llama_decode(entry->ctx, batch) != 0) {
                error = true;
                error_text = "推理中断（decode 失败）";
                break;
            }
        }
    }

    llama_sampler_free(smpl);
    entry->busy.store(false);

    GenMsg * done = new GenMsg();
    done->done = true;
    done->is_error = error;
    done->text = error ? error_text : full;
    napi_call_threadsafe_function(tsfn, done, napi_tsfn_blocking);
    napi_release_threadsafe_function(tsfn, napi_tsfn_release);
}

napi_value get_version(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    const char * text = "llama.cpp (MoyiOhos NAPI bridge)";
    napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value load_model(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_error(env, nullptr, "loadModel 需要模型路径");
        return nullptr;
    }
    char path[1024];
    size_t len = 0;
    if (napi_get_value_string_utf8(env, args[0], path, sizeof(path), &len) != napi_ok) {
        napi_throw_error(env, nullptr, "模型路径无效");
        return nullptr;
    }

    llama_backend_init();
    llama_model_params mparams = llama_model_default_params();
    llama_model * model = llama_model_load_from_file(path, mparams);
    if (model == nullptr) {
        napi_throw_error(env, nullptr, "模型加载失败：文件损坏或量化类型不受支持（含 1.25bit STQ1_0 本版暂不支持）");
        return nullptr;
    }
    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 2048;
    llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == nullptr) {
        llama_model_free(model);
        napi_throw_error(env, nullptr, "上下文创建失败（内存不足或模型不兼容）");
        return nullptr;
    }

    ModelEntry * entry = new ModelEntry();
    entry->model = model;
    entry->ctx = ctx;

    std::lock_guard<std::mutex> lock(g_mutex);
    int handle = g_next_handle++;
    g_entries[handle] = entry;

    napi_value result = nullptr;
    napi_create_int32(env, handle, &result);
    return result;
}

napi_value generate(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value args[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 6) {
        napi_throw_error(env, nullptr, "generate 参数不足");
        return nullptr;
    }
    int32_t handle = 0;
    napi_get_value_int32(env, args[0], &handle);

    std::string prompt;
    size_t plen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &plen);
    prompt.resize(plen);
    napi_get_value_string_utf8(env, args[1], &prompt[0], plen + 1, &plen);

    int32_t maxTokens = 128;
    napi_get_value_int32(env, args[2], &maxTokens);
    double temperature = 0.3;
    napi_get_value_double(env, args[3], &temperature);

    ModelEntry * entry = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_entries.find(handle);
        if (it != g_entries.end()) {
            entry = it->second;
        }
    }
    if (entry == nullptr) {
        napi_throw_error(env, nullptr, "模型句柄无效或已卸载");
        return nullptr;
    }
    if (entry->busy.load()) {
        napi_throw_error(env, nullptr, "该模型正在生成中");
        return nullptr;
    }
    entry->busy.store(true);
    entry->stop.store(false);

    GenCallbacks * cbs = new GenCallbacks();
    napi_create_reference(env, args[4], 1, &cbs->on_token);
    napi_create_reference(env, args[5], 1, &cbs->on_done);

    napi_value resource_name = nullptr;
    napi_create_string_utf8(env, "llamacpp_generate", NAPI_AUTO_LENGTH, &resource_name);

    napi_threadsafe_function tsfn = nullptr;
    napi_status status = napi_create_threadsafe_function(
        env, nullptr, nullptr, resource_name, 0, 1, nullptr, finalize_callbacks, cbs, call_js, &tsfn);
    if (status != napi_ok) {
        entry->busy.store(false);
        napi_delete_reference(env, cbs->on_token);
        napi_delete_reference(env, cbs->on_done);
        delete cbs;
        napi_throw_error(env, nullptr, "线程安全回调创建失败");
        return nullptr;
    }

    std::thread worker(run_generation, env, tsfn, entry, prompt, static_cast<int>(maxTokens),
                       static_cast<float>(temperature));
    worker.detach();

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value stop_generation(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t handle = 0;
    if (argc >= 1) {
        napi_get_value_int32(env, args[0], &handle);
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_entries.find(handle);
    if (it != g_entries.end()) {
        it->second->stop.store(true);
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value unload_model(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t handle = 0;
    if (argc >= 1) {
        napi_get_value_int32(env, args[0], &handle);
    }
    ModelEntry * entry = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_entries.find(handle);
        if (it != g_entries.end()) {
            entry = it->second;
            g_entries.erase(it);
        }
    }
    if (entry != nullptr) {
        entry->stop.store(true);
        if (entry->ctx != nullptr) {
            llama_free(entry->ctx);
        }
        if (entry->model != nullptr) {
            llama_model_free(entry->model);
        }
        delete entry;
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"getVersion", nullptr, get_version, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadModel", nullptr, load_model, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generate", nullptr, generate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopGeneration", nullptr, stop_generation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"unloadModel", nullptr, unload_model, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_llamacpp_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "llamacpp",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterLlamaCppModule(void) {
    napi_module_register(&g_llamacpp_module);
}

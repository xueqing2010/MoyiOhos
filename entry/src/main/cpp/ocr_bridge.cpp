// Native async-capable PP-OCR rec bridge: ONNX Runtime C API.
// Det stays in ArkTS; this module only runs rec boxes on the calling thread,
// so ArkTS can invoke it from TaskPool/Worker without JS ORT session issues.

#include <napi/native_api.h>
#include "onnxruntime_c_api.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

const OrtApi * g_api = nullptr;
OrtEnv * g_env = nullptr;
OrtSession * g_session = nullptr;
OrtSession * g_det_session = nullptr;
OrtSessionOptions * g_options = nullptr;
OrtMemoryInfo * g_memory = nullptr;
OrtAllocator * g_allocator = nullptr;
std::mutex g_mutex;
std::string g_input_name;
std::string g_output_name;
std::string g_det_input_name;
std::string g_det_output_name;

bool ensure_api() {
    if (g_api == nullptr) {
        g_api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    }
    return g_api != nullptr;
}

bool ensure_env() {
    if (!ensure_api()) return false;
    if (g_env == nullptr) {
        if (g_api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "MoyiOcr", &g_env) != nullptr) {
            g_env = nullptr;
            return false;
        }
        if (g_api->GetAllocatorWithDefaultOptions(&g_allocator) != nullptr) return false;
        if (g_api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_memory) != nullptr) return false;
    }
    return true;
}

bool init_rec(const std::string & model_path) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!ensure_env()) return false;
    if (g_session != nullptr) {
        g_api->ReleaseSession(g_session);
        g_session = nullptr;
    }
    if (g_options == nullptr) {
        if (g_api->CreateSessionOptions(&g_options) != nullptr) return false;
        g_api->SetIntraOpNumThreads(g_options, 2);
        g_api->SetSessionGraphOptimizationLevel(g_options, ORT_ENABLE_ALL);
    }
    if (g_api->CreateSession(g_env, model_path.c_str(), g_options, &g_session) != nullptr) {
        g_session = nullptr;
        return false;
    }
    char * name = nullptr;
    if (g_api->SessionGetInputName(g_session, 0, g_allocator, &name) != nullptr || name == nullptr) return false;
    g_input_name = name;
    g_allocator->Free(g_allocator, name);
    name = nullptr;
    if (g_api->SessionGetOutputName(g_session, 0, g_allocator, &name) != nullptr || name == nullptr) return false;
    g_output_name = name;
    g_allocator->Free(g_allocator, name);
    return true;
}

inline void sample_rgb(const unsigned char * rgba, int w, int h, float fx, float fy, float out[3]);

bool init_det(const std::string & model_path) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!ensure_env()) return false;
    if (g_det_session != nullptr) {
        g_api->ReleaseSession(g_det_session);
        g_det_session = nullptr;
    }
    if (g_options == nullptr) {
        if (g_api->CreateSessionOptions(&g_options) != nullptr) return false;
        g_api->SetIntraOpNumThreads(g_options, 2);
        g_api->SetSessionGraphOptimizationLevel(g_options, ORT_ENABLE_ALL);
    }
    if (g_api->CreateSession(g_env, model_path.c_str(), g_options, &g_det_session) != nullptr) {
        g_det_session = nullptr;
        return false;
    }
    char * name = nullptr;
    if (g_api->SessionGetInputName(g_det_session, 0, g_allocator, &name) != nullptr || name == nullptr) return false;
    g_det_input_name = name;
    g_allocator->Free(g_allocator, name);
    name = nullptr;
    if (g_api->SessionGetOutputName(g_det_session, 0, g_allocator, &name) != nullptr || name == nullptr) return false;
    g_det_output_name = name;
    g_allocator->Free(g_allocator, name);
    return true;
}

struct DetBox { int x; int y; int w; int h; };

std::vector<DetBox> detect_boxes(const unsigned char * rgba, int w, int h) {
    std::vector<DetBox> result;
    if (g_det_session == nullptr || g_api == nullptr || w <= 0 || h <= 0) return result;
    const int DET_MAX_SIDE = 768;
    float scale = 1.0f;
    int max_side = std::max(w, h);
    if (max_side > DET_MAX_SIDE) scale = (float)DET_MAX_SIDE / (float)max_side;
    int detW = std::max(32, (int)std::round((float)w * scale / 32.0f) * 32);
    int detH = std::max(32, (int)std::round((float)h * scale / 32.0f) * 32);
    std::vector<float> input((size_t)3 * detH * detW, 0.0f);
    size_t plane = (size_t)detW * detH;
    for (int y = 0; y < detH; ++y) {
        float sy = (y + 0.5f) * h / detH - 0.5f;
        for (int x = 0; x < detW; ++x) {
            float sx = (x + 0.5f) * w / detW - 0.5f;
            float rgb[3];
            sample_rgb(rgba, w, h, sx, sy, rgb);
            size_t idx = (size_t)y * detW + x;
            input[idx] = (rgb[0] / 255.0f - 0.5f) / 0.5f;
            input[plane + idx] = (rgb[1] / 255.0f - 0.5f) / 0.5f;
            input[plane * 2 + idx] = (rgb[2] / 255.0f - 0.5f) / 0.5f;
        }
    }
    int64_t dims[4] = {1, 3, detH, detW};
    OrtValue * tensor = nullptr;
    if (g_api->CreateTensorWithDataAsOrtValue(g_memory, input.data(), input.size() * sizeof(float),
        dims, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &tensor) != nullptr) {
        return result;
    }
    const char * input_names[1] = {g_det_input_name.c_str()};
    const char * output_names[1] = {g_det_output_name.c_str()};
    OrtValue * output = nullptr;
    if (g_api->Run(g_det_session, nullptr, input_names, &tensor, 1, output_names, 1, &output) == nullptr && output != nullptr) {
        OrtTensorTypeAndShapeInfo * info = nullptr;
        if (g_api->GetTensorTypeAndShape(output, &info) == nullptr && info != nullptr) {
            size_t count = 0;
            g_api->GetDimensionsCount(info, &count);
            std::vector<int64_t> shape(count);
            if (count >= 2) g_api->GetDimensions(info, shape.data(), count);
            float * data = nullptr;
            if (count >= 2 && g_api->GetTensorMutableData(output, (void **)&data) == nullptr && data != nullptr) {
                int predH = (int)shape[count - 2];
                int predW = (int)shape[count - 1];
                std::vector<unsigned char> mask((size_t)predW * predH, 0);
                for (size_t i = 0; i < mask.size(); ++i) mask[i] = data[i] > 0.3f ? 1 : 0;
                std::vector<unsigned char> tmp(mask.size(), 0);
                const int radius = 3;
                for (int y = 0; y < predH; ++y) {
                    for (int x = 0; x < predW; ++x) {
                        if (!mask[(size_t)y * predW + x]) continue;
                        int x0 = std::max(0, x - radius), x1 = std::min(predW - 1, x + radius);
                        for (int nx = x0; nx <= x1; ++nx) tmp[(size_t)y * predW + nx] = 1;
                    }
                }
                std::vector<unsigned char> dilated(mask.size(), 0);
                for (int y = 0; y < predH; ++y) {
                    for (int x = 0; x < predW; ++x) {
                        if (!tmp[(size_t)y * predW + x]) continue;
                        int y0 = std::max(0, y - radius), y1 = std::min(predH - 1, y + radius);
                        for (int ny = y0; ny <= y1; ++ny) dilated[(size_t)ny * predW + x] = 1;
                    }
                }
                std::vector<unsigned char> visited(dilated.size(), 0);
                std::vector<int> stack;
                float sx = (float)w / predW;
                float sy = (float)h / predH;
                for (int i = 0; i < (int)dilated.size(); ++i) {
                    if (!dilated[i] || visited[i]) continue;
                    int minX = predW, maxX = 0, minY = predH, maxY = 0, cc = 0;
                    stack.push_back(i);
                    visited[i] = 1;
                    while (!stack.empty()) {
                        int idx = stack.back();
                        stack.pop_back();
                        int x = idx % predW;
                        int y = idx / predW;
                        ++cc;
                        minX = std::min(minX, x); maxX = std::max(maxX, x);
                        minY = std::min(minY, y); maxY = std::max(maxY, y);
                        if (x > 0 && dilated[idx - 1] && !visited[idx - 1]) { visited[idx - 1] = 1; stack.push_back(idx - 1); }
                        if (x + 1 < predW && dilated[idx + 1] && !visited[idx + 1]) { visited[idx + 1] = 1; stack.push_back(idx + 1); }
                        if (y > 0 && dilated[idx - predW] && !visited[idx - predW]) { visited[idx - predW] = 1; stack.push_back(idx - predW); }
                        if (y + 1 < predH && dilated[idx + predW] && !visited[idx + predW]) { visited[idx + predW] = 1; stack.push_back(idx + predW); }
                    }
                    if (cc < 12) continue;
                    DetBox box;
                    box.x = std::max(0, (int)std::floor(minX * sx));
                    box.y = std::max(0, (int)std::floor(minY * sy));
                    box.w = std::min(w - box.x, (int)std::ceil((maxX - minX + 1) * sx));
                    box.h = std::min(h - box.y, (int)std::ceil((maxY - minY + 1) * sy));
                    if (box.w < 8 || box.h < 8) continue;
                    int ex = (int)std::round(box.w * 0.12f);
                    int ey = (int)std::round(box.h * 0.12f);
                    box.x = std::max(0, box.x - ex);
                    box.y = std::max(0, box.y - ey);
                    box.w = std::min(w - box.x, box.w + ex * 2);
                    box.h = std::min(h - box.y, box.h + ey * 2);
                    result.push_back(box);
                    if (result.size() >= 80) break;
                }
                bool changed = true;
                while (changed) {
                    changed = false;
                    for (size_t i = 0; i < result.size() && !changed; ++i) {
                        for (size_t j = i + 1; j < result.size(); ++j) {
                            const DetBox & a = result[i];
                            const DetBox & b = result[j];
                            const int gap = 8;
                            bool near = a.x - gap <= b.x + b.w && b.x - gap <= a.x + a.w
                                && a.y - gap <= b.y + b.h && b.y - gap <= a.y + a.h;
                            if (near) {
                                int x0 = std::min(a.x, b.x), y0 = std::min(a.y, b.y);
                                int x1 = std::max(a.x + a.w, b.x + b.w), y1 = std::max(a.y + a.h, b.y + b.h);
                                result[i].x = x0; result[i].y = y0; result[i].w = x1 - x0; result[i].h = y1 - y0;
                                result.erase(result.begin() + j);
                                changed = true;
                                break;
                            }
                        }
                    }
                }
            }
            g_api->ReleaseTensorTypeAndShapeInfo(info);
        }
    }
    if (output != nullptr) g_api->ReleaseValue(output);
    g_api->ReleaseValue(tensor);
    return result;
}

inline void sample_rgb(const unsigned char * rgba, int w, int h, float fx, float fy, float out[3]) {
    float x = std::max(0.0f, std::min((float)w - 1.0f, fx));
    float y = std::max(0.0f, std::min((float)h - 1.0f, fy));
    int x0 = (int)std::floor(x);
    int y0 = (int)std::floor(y);
    int x1 = std::min(w - 1, x0 + 1);
    int y1 = std::min(h - 1, y0 + 1);
    float wx = x - x0;
    float wy = y - y0;
    for (int c = 0; c < 3; ++c) {
        float top = rgba[(y0 * w + x0) * 4 + c] * (1.0f - wx) + rgba[(y0 * w + x1) * 4 + c] * wx;
        float bottom = rgba[(y1 * w + x0) * 4 + c] * (1.0f - wx) + rgba[(y1 * w + x1) * 4 + c] * wx;
        out[c] = top * (1.0f - wy) + bottom * wy;
    }
}

std::string rec_one(const unsigned char * rgba, int w, int h,
                    int bx, int by, int bw, int bh, const std::vector<std::string> & dict) {
    const int REC_H = 48;
    int pad = 2;
    int x0 = std::max(0, bx - pad);
    int y0 = std::max(0, by - pad);
    int x1 = std::min(w, bx + bw + pad);
    int y1 = std::min(h, by + bh + pad);
    int cw = std::max(1, x1 - x0);
    int ch = std::max(1, y1 - y0);
    int target_w = (int)std::ceil((float)REC_H * cw / ch);
    target_w = std::max(32, (int)std::ceil(target_w / 32.0f) * 32);
    target_w = std::min(target_w, 1280);
    std::vector<float> input((size_t)3 * REC_H * target_w, 0.0f);
    int used_w = (int)std::ceil((float)REC_H * cw / ch);
    for (int y = 0; y < REC_H; ++y) {
        float sy = y0 + (y + 0.5f) * ch / REC_H - 0.5f;
        for (int x = 0; x < target_w; ++x) {
            if (x >= used_w) continue;
            float sx = x0 + (x + 0.5f) * cw / used_w - 0.5f;
            float rgb[3];
            sample_rgb(rgba, w, h, sx, sy, rgb);
            size_t base = (size_t)y * target_w + x;
            input[base] = (rgb[0] / 255.0f - 0.5f) / 0.5f;
            input[REC_H * target_w + base] = (rgb[1] / 255.0f - 0.5f) / 0.5f;
            input[2 * REC_H * target_w + base] = (rgb[2] / 255.0f - 0.5f) / 0.5f;
        }
    }
    int64_t dims[4] = {1, 3, REC_H, target_w};
    OrtValue * tensor = nullptr;
    if (g_api->CreateTensorWithDataAsOrtValue(g_memory, input.data(), input.size() * sizeof(float),
        dims, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &tensor) != nullptr) {
        return "";
    }
    const char * input_names[1] = {g_input_name.c_str()};
    const char * output_names[1] = {g_output_name.c_str()};
    OrtValue * output = nullptr;
    std::string text;
    if (g_api->Run(g_session, nullptr, input_names, &tensor, 1, output_names, 1, &output) == nullptr && output != nullptr) {
        OrtTensorTypeAndShapeInfo * info = nullptr;
        if (g_api->GetTensorTypeAndShape(output, &info) == nullptr && info != nullptr) {
            size_t count = 0;
            g_api->GetDimensionsCount(info, &count);
            std::vector<int64_t> shape(count);
            if (count > 0) g_api->GetDimensions(info, shape.data(), count);
            float * data = nullptr;
            if (g_api->GetTensorMutableData(output, (void **)&data) == nullptr && data != nullptr && count >= 2) {
                int seq = (int)shape[count - 2];
                int classes = (int)shape[count - 1];
                int prev = -1;
                for (int t = 0; t < seq; ++t) {
                    int best = 0;
                    float prob = data[(size_t)t * classes];
                    for (int c = 1; c < classes; ++c) {
                        float p = data[(size_t)t * classes + c];
                        if (p > prob) { prob = p; best = c; }
                    }
                    if (best > 0 && best != prev && best < (int)dict.size()) text += dict[best];
                    prev = best;
                }
            }
            g_api->ReleaseTensorTypeAndShapeInfo(info);
        }
    }
    if (output != nullptr) g_api->ReleaseValue(output);
    g_api->ReleaseValue(tensor);
    return text;
}

napi_value init_rec_js(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) { napi_throw_error(env, nullptr, "initRec 需要模型路径"); return nullptr; }
    char path[1024];
    size_t len = 0;
    if (napi_get_value_string_utf8(env, args[0], path, sizeof(path), &len) != napi_ok) return nullptr;
    bool ok = init_rec(std::string(path, len));
    napi_value result = nullptr;
    napi_get_boolean(env, ok, &result);
    return result;
}

napi_value recognize_boxes(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 5) { napi_throw_error(env, nullptr, "recognizeBoxes 参数不足"); return nullptr; }
    void * raw = nullptr;
    size_t raw_len = 0;
    if (napi_get_arraybuffer_info(env, args[0], &raw, &raw_len) != napi_ok) return nullptr;
    int32_t w = 0, h = 0;
    napi_get_value_int32(env, args[1], &w);
    napi_get_value_int32(env, args[2], &h);
    uint32_t box_count = 0;
    napi_get_array_length(env, args[3], &box_count);
    std::vector<int> boxes(box_count);
    for (uint32_t i = 0; i < box_count; ++i) {
        napi_value item = nullptr;
        napi_get_element(env, args[3], i, &item);
        int32_t v = 0;
        napi_get_value_int32(env, item, &v);
        boxes[i] = v;
    }
    size_t dict_len = 0;
    napi_get_value_string_utf8(env, args[4], nullptr, 0, &dict_len);
    std::string dict_text(dict_len, '\0');
    if (dict_len > 0) napi_get_value_string_utf8(env, args[4], &dict_text[0], dict_len + 1, &dict_len);
    std::vector<std::string> dict;
    dict.push_back("");
    size_t start = 0;
    for (size_t i = 0; i <= dict_text.size(); ++i) {
        if (i == dict_text.size() || dict_text[i] == '\n') {
            std::string line = dict_text.substr(start, i - start);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (!line.empty()) dict.push_back(line);
            start = i + 1;
        }
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    napi_value arr = nullptr;
    napi_create_array_with_length(env, box_count / 4, &arr);
    if (g_session != nullptr && w > 0 && h > 0) {
        const unsigned char * rgba = (const unsigned char *)raw;
        for (uint32_t i = 0, j = 0; i + 3 < box_count; i += 4, ++j) {
            std::string text = rec_one(rgba, w, h, boxes[i], boxes[i + 1], boxes[i + 2], boxes[i + 3], dict);
            napi_value s = nullptr;
            napi_create_string_utf8(env, text.c_str(), text.size(), &s);
            napi_set_element(env, arr, j, s);
        }
    }
    return arr;
}

napi_value init_det_js(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) { napi_throw_error(env, nullptr, "initDet 需要模型路径"); return nullptr; }
    char path[1024];
    size_t len = 0;
    if (napi_get_value_string_utf8(env, args[0], path, sizeof(path), &len) != napi_ok) return nullptr;
    bool ok = init_det(std::string(path, len));
    napi_value result = nullptr;
    napi_get_boolean(env, ok, &result);
    return result;
}

napi_value detect_js(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) { napi_throw_error(env, nullptr, "detectBoxes 参数不足"); return nullptr; }
    void * raw = nullptr;
    size_t raw_len = 0;
    if (napi_get_arraybuffer_info(env, args[0], &raw, &raw_len) != napi_ok) return nullptr;
    int32_t w = 0, h = 0;
    napi_get_value_int32(env, args[1], &w);
    napi_get_value_int32(env, args[2], &h);
    std::lock_guard<std::mutex> lock(g_mutex);
    std::vector<DetBox> boxes = detect_boxes((const unsigned char *)raw, w, h);
    napi_value arr = nullptr;
    napi_create_array_with_length(env, boxes.size() * 4, &arr);
    uint32_t k = 0;
    for (const auto & b : boxes) {
        napi_value v = nullptr;
        napi_create_int32(env, b.x, &v); napi_set_element(env, arr, k++, v);
        napi_create_int32(env, b.y, &v); napi_set_element(env, arr, k++, v);
        napi_create_int32(env, b.w, &v); napi_set_element(env, arr, k++, v);
        napi_create_int32(env, b.h, &v); napi_set_element(env, arr, k++, v);
    }
    return arr;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"initRec", nullptr, init_rec_js, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initDet", nullptr, init_det_js, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detectBoxes", nullptr, detect_js, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"recognizeBoxes", nullptr, recognize_boxes, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_ocr_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ocrasync",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterOcrModule(void) {
    napi_module_register(&g_ocr_module);
}

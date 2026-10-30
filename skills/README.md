# Skills

本目录存放可复用的开发方法论。

## harmonyos-arkts-app-dev

HarmonyOS NEXT（ArkTS / ArkUI，API 26）应用从零开发、移植、签名、真机验证的完整 skill。

- 入口：[harmonyos-arkts-app-dev/SKILL.md](harmonyos-arkts-app-dev/SKILL.md)
- 适用：多端 UI、OCR/ONNX、llama.cpp、翻译、Account Kit、AGC 签名、Cloud Foundation Kit、devecocli 自动化。
- 结构：
  - SKILL.md：主流程与铁律
  - references/：架构、UI、OCR、翻译、账号签名、测试、全量坑位、案例复盘
  - scripts/doctor.sh：项目/设备/签名/权限只读体检
  - scripts/install-deveco-skills.sh：批量安装 DevEco 官方 skills（默认 30 个，可选 --all）

## 安装到 DSH（可选）

把整个目录复制到用户级 skills 目录（不同 DSH 版本可能不同，先确认当前版本的 skills 路径）：

    mkdir -p ~/.dsh/skills
    cp -R skills/harmonyos-arkts-app-dev ~/.dsh/skills/

或直接把 [harmonyos-arkts-app-dev/SKILL.md](harmonyos-arkts-app-dev/SKILL.md) 作为提示词/知识文件加载。

## 使用方式

- 新项目：从 SKILL.md 的 Phase 0 开始逐阶段过门槛；
- 遇到报错：先查 references/pitfalls.md 的错误码/现象；
- 换签名/账号：查 references/account-sign-cloud.md；
- OCR/模型：查 references/ocr-and-models.md；
- 真机测试：查 references/testing-and-automation.md，并运行 doctor.sh。

# 可复现的解析输出

输入为仓库内原创合成样本 `fixtures/v4-all-records-le.stdf`，无客户数据。
在仓库根目录执行：

```sh
moon build --target js --deny-warn
python tools/generate_demo.py
python tools/generate_demo.py --check
```

生成器直接调用真实 MoonBit CLI 的 `validate`，成功后调用 `dump`，仅调整 JSON 空白格式，不增删字段、数值或原始字节。

- `validation.json`：完整结构化校验结果，27 条记录、25 种类型、无诊断。
- `records.jsonl`：27 条记录的全部字段、源偏移、表示和原始记录体。
- `ptr-record.json`：从完整导出提取的一条 PTR，含全部 20 个字段。
- `preview.html`：将上述实际输出排版展示，可本地打开。

README 中的 [输出截图](../../docs/images/stdf-v4-json-output.jpg) 于 2026-11-18 从该预览实际截取，未人工改写输出值。截图用于阅读，JSON 文件用于机器复核；CI 用 `--check` 比较示例与当前 CLI 输出。新增生成内容属于文档示例，核心解析仍由 MoonBit 完成。

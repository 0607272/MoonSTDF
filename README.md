# MoonSTDF

[![CI](https://github.com/0607272/MoonSTDF/actions/workflows/ci.yml/badge.svg)](https://github.com/0607272/MoonSTDF/actions/workflows/ci.yml)

MoonBit 实现的半导体 STDF V4 测试数据解析与离线分析工具。核心库支持增量分帧、多站点芯片关联、良率与测试项分布、显式复测策略和批次比较；Node CLI 与浏览器工作台共用同一套 MoonBit 逻辑。

适用于测试工程师整理 ATE 文件、工艺工程师比较批次，以及教学环境演示芯片测试数据。它是 STDF V4 的**部分记录和字段实现**，详细边界见 [支持矩阵](docs/compatibility.md)。

## 快速开始

安装 [MoonBit 官方工具链](https://www.moonbitlang.com/download/)；本项目验证版本为 `moonc v0.10.20+65efd5b93`、`moon 0.1.20261104`。CLI 需要 Node.js 22+，辅助脚本需要 Python 3.10+。核心库无第三方运行时依赖。无需 Python 包安装。

```sh
git clone https://github.com/0607272/MoonSTDF.git
cd MoonSTDF
moon check --target all --deny-warn
moon test --target wasm-gc --deny-warn
moon run examples/demo --target wasm-gc
moon build --target js --deny-warn
node _build/js/debug/build/cmd/main/main.js analyze fixtures/lot-a-le.stdf
```

样本产生 27 条记录、2 个芯片观测、1 通过 / 1 失败、良率 `0.5`；PTR 100 均值 `2.5 V`。3 条 PMR 保留为未投影记录。便携示例另用内嵌的最小文件，故会报告缺少 MIR/MRR 的诊断。

## 文件分析、比较与复测

```sh
node _build/js/debug/build/cmd/main/main.js analyze fixtures/lot-a-le.stdf --format html --output lot.html
node _build/js/debug/build/cmd/main/main.js analyze fixtures/lot-a-le.stdf --format csv --output parts.csv
node _build/js/debug/build/cmd/main/main.js analyze fixtures/lot-a-le.stdf --policy last --identity coordinates
node _build/js/debug/build/cmd/main/main.js compare fixtures/lot-a-le.stdf fixtures/lot-b-le.stdf
node _build/js/debug/build/cmd/main/main.js retest fixtures/lot-a-le.stdf fixtures/retest-le.stdf --identity coordinates
```

比较样本的 PTR 均值差为 `+1 V`；复测样本匹配 2 颗、恢复 1 颗、退化 0 颗。比较要求测试种类、编号、单位、上下限及等号策略一致；差异或缺失条件产生诊断。跨文件复测要求配对唯一；重复、缺失和冲突身份会报告，不能据此自动判定量产放行。

CLI 默认输出 JSON，可用 `--output PATH` 保存；父目录须已存在。结构错误返回退出码 2，诊断保留在报告中；`compare` / `retest` 的源诊断标注 before/after。`--help` 查看参数。文件每次读取 64 KiB，默认每文件上限 256 MiB / 1,000,000 条记录。解析有界，但分析保留芯片观测与未投影记录，内存不恒定。

## 浏览器本地分析

```sh
moon build --target js --deny-warn
python tools/build_web.py
```

直接在浏览器打开 `web/index.html`，选择合成样本或自己的未压缩 STDF V4 文件，可查看测试项分布、SVG 晶圆坐标图并下载 JSON/HTML。页面不上传文件、不请求 CDN。编译产物 `web/moonstdf.js` 由以上命令生成，不纳入源码。页面在主线程分析，接近资源上限的文件可能短暂阻塞界面；浏览器入口目前提供单文件观测分析，复测与比较使用 CLI。

## MoonBit API

在 MoonBit 工程的 `moon.pkg` 中导入 `"0607272/moonstdf"`，并使用本地路径依赖或源码检出；当前尚未发布 Mooncakes 包。

```moonbit
fn inspect_file(data : Bytes) -> String raise @moonstdf.StdfError {
  let analysis = @moonstdf.analyze(data)
  @moonstdf.report_json(analysis)
}
```

大文件可用 `Framer::new().feed(chunk)` 获得 `Frame`，逐条传给 `Analyzer::accept`，在 EOF 依次调用两者的 `finish()`。遇到错误后对象关闭，不可继续使用；直接传 Frame 也校验 FAR、字节序、体长及预算。`Analyzer::new(max_bytes=..., max_records=...)` 可配置小于默认值的预算。完整 API 见 [生成接口](pkg.generated.mbti) 与 [便携示例](examples/demo/main.mbt)。

## 统计口径

- 默认保留所有完成的芯片观测；良率 = 正常通过 /（正常通过 + 正常失败）。未知、异常结束单列且不进分母，空分母为 `null`。
- PTR/MPR 数值已经是基本单位；显示缩放不参与数值计算。按首条同类同号记录建立不可变基线，后续覆盖只影响当前记录。
- 分布只纳入有限且质量有效的数值；失败但数值有效的样本仍可参与分布。MPR 多个值增加样本数，不增加执行数；标准差采用总体口径。
- `first` / `last` 必须显式选择，并指定 `coordinates` 或 `part-id` 身份。坐标键含 lot/wafer；缺失和冲突不会被静默合并。选择后停用与全文件汇总的直接比较。
- 晶圆图采用原始逻辑坐标，不转换物理方向；重复坐标按后观测覆盖并显式提示。坐标不等于全球唯一芯片标识。

## 验证与持续集成

```sh
moon fmt --check
moon info
git diff --exit-code -- '*.mbti'
moon check --target all --deny-warn
moon build --target wasm --deny-warn
moon test --target wasm --deny-warn
moon build --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --deny-warn
moon test --target js --deny-warn
python tools/generate_fixtures.py --check
python tools/test_cli.py
python tools/build_web.py
python tools/test_web.py
```

CI 覆盖 JS / Wasm / WasmGC 的 check、build、test 和运行示例，另校验格式、接口漂移、样本可复现性与 CLI/浏览器共享核心一致性。Native 尚未列为支持目标；Windows 本地缺少 MSVC Build Tools，未完成 Native 运行验证。浏览器核心已在 Node 下验证，实际浏览器布局和文件选择流程仍需交互验证。

所有二进制样本均为原创合成数据，见 [fixtures](fixtures/README.md)。五个合法样本已用独立 MIT 解码器 Semi-ATE-STDF 0.1.28 对照记录数量、原始值、状态与身份字段；不等于覆盖所有厂商文件。见 [来源与许可证](docs/provenance.md)。

## 限制与后续方向

不支持 STDF V4-2007 扩展、压缩封装、ATDF、写回 STDF、硬件采集、SPC 显著性检验或完整标准符合性认证。汇总记录的一致性检查也不能证明输入文件完整。后续可扩展厂商样本验证、PMR 引脚投影和 Worker 分析入口。

源码与原创合成样本采用 [MIT](LICENSE) 许可证。

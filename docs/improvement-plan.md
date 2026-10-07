# Shuttle 改进计划

- 创建：2026-10-06
- 依据：全量代码审查（通读源码、Xcode 27 构建、Clang 静态分析、现有测试、临时测试程序实测）
- 用法：每个步骤对应一个独立提交；做完在「进度」里勾选，勾选和该步骤的改动放在同一个提交里（提交号查 git log）。文中行号以 `b59983b` 为准，改动后会漂移，以函数名为准。

## 进度

- [x] 0.1 部署目标改为 12.0
- [x] 0.2 测试基建（smoke test 改 ARC、新增回归测试、接入 CI）
- [x] 1.1 菜单每次打开都重建 + 反复设置开机启动
- [x] 1.2 布尔配置项类型检查（与 1.1 一起上线）
- [x] 1.3 ssh config 解析：空 Host、通配符
- [x] 1.4 同名主机/分组被吞
- [x] 2.1 配置错误不再强制退出
- [x] 2.2 About 窗口泄漏
- [ ] 2.3 导入/导出
- [ ] 2.4 编辑器命令 + 菜单项 target
- [ ] 2.5 终端启动移出主线程
- [ ] 2.6 LaunchAtLoginController 泄漏（仅 D1 选 12.0 时）
- [ ] 3.1 清理 TerminalManager 死代码
- [ ] 3.2 清理 AppDelegate 死代码与旧系统分支
- [ ] 3.3 清理无用资源与脚本
- [ ] 4.1 本地化补全
- [ ] 4.2 Release 构建脚本
- [ ] 4.3 固定签名（可选）
- [ ] 5.1 验证 Terminal.app 冷启动是否多开窗口

## 当前基线（2026-10-06）

| 检查 | 结果 |
|---|---|
| `./scripts/build-debug.sh`（Xcode 27） | 失败：部署目标 11.0 低于最低支持的 12.0 |
| 加 `MACOSX_DEPLOYMENT_TARGET=12.0` 覆盖后构建 | 成功，0 警告 |
| `xcodebuild ... analyze` | 3 个警告：`AboutWindowController.m:25`、`AppDelegate.m:1013`、`LaunchAtLoginController.m:136` |
| `python3 tests/test_config_fixtures.py` | 3 个测试通过 |
| `python3 tests/test_openhost_smoke.py` | 1 个测试通过（未接入 CI） |

## 约束与历史教训

- dd9e5a9 把清理和启动流程的行为改动放在一个提交里，随后被 a8f3b8a 整体回滚。所以每个提交只做一件事，清理和行为变化分开。
- bc4424a（`inTerminal` / `open_in` 大小写归一化）已被 a195250 回滚，本计划不重新引入。
- 保留旧的 `¬_¬` 字符串菜单载荷的解析（smoke test 覆盖），新代码只生成字典载荷。
- iTerm 冷启动的行为保持不变：复用启动 tab、按 tty 匹配、不靠反复启动 osascript 来轮询。
- 改动只有重新构建并替换 `/Applications/Shuttle.app` 后才对日常使用生效，替换由你手动完成。
- 每个提交的验收底线：构建通过，两个现有测试和新增回归测试全部通过。

## 决定事项（2026-10-06 确认按推荐做法执行）

| 编号 | 问题 | 决定 |
|---|---|---|
| D1 | 部署目标设为 12.0 还是 13.0 | 12.0。13.0 以后需要时再单独做，届时整套旧版开机启动实现（MRC 文件）可以删掉 |
| D2 | 同名主机 / 同名分组怎么显示 | 全部显示，同名分组合并 |
| D3 | `inTerminal` 值非法时怎么办 | 弹警告（只有 OK 按钮），不执行这条命令 |
| D4 | 是否配置固定的本地签名证书 | 暂不做，保留为可选步骤 4.3 |

## 阶段 0：解锁构建、补测试基建

### 0.1 部署目标

- 现状：`Shuttle.xcodeproj/project.pbxproj` 里 project 级是 11.5（第 416、461 行），target 级是 11.0（第 479、500 行），Xcode 27 拒绝编译。
- 做法：按 D1 统一为 12.0，只在 project 级保留一处，删掉 target 级的覆盖。`Shuttle-Info.plist` 的 `LSMinimumSystemVersion` 引用这个变量，会自动跟随。
- 验收：不带任何覆盖参数运行 `./scripts/build-debug.sh` 成功；`analyze` 没有新增警告。

### 0.2 测试基建

- smoke test 改用 ARC 编译，和工程设置一致：`LaunchAtLoginController.m` 单独用 `-fno-objc-arc -c` 编译成 `.o` 再链接，其余源码用 `-fobjc-arc`。现在是全部用 `-fno-objc-arc` 编译。
- 新增 `tests/regression.m` 和 `tests/test_regression.py`，编译方式同上。写法要点（已在临时测试程序里验证可行）：
  - 用 KVC 注入 AppDelegate 的 ivar：`menu`、`shuttleConfigFile`、`shuttleAltConfigFile`、`parseAltJSON`、`launchAtLoginController`；
  - 用一个假对象替换 `launchAtLoginController`，统计 `setLaunchAtLogin:` 被调用的次数，不碰真实的 SMAppService；
  - 配置文件写到临时目录；ssh 解析直接对 fixture 文件调用 `parseSSHConfig:`。
- `.github/workflows/macos-build.yml` 增加两步：运行 `tests/test_openhost_smoke.py` 和 `tests/test_regression.py`。
- README 的 Test 一节补上这两个命令。
- 验收：本地三套测试全部通过。

## 阶段 1：已实测确认的 bug（每条都附回归用例）

### 1.1 菜单每次打开都重建，并反复设置开机启动

- 现状：`show_ssh_config_hosts: false`（你的配置就是这样）时，`sshConfigModifiedTimes` 一直是 nil，`sshConfigFilesNeedUpdate`（`AppDelegate.m:273-279`）只要 `/etc/ssh/ssh_config` 存在就返回 YES；而 `loadMenu` 每次都会执行 `launchAtLoginController.launchAtLogin = ...`（`:511`）。
- 证据：实测打开 3 次菜单，重建 3 次、`setLaunchAtLogin:` 调用 3 次；正在运行的 Shuttle 日志里有 `Failed to update launch-at-login setting ... SMAppServiceErrorDomain Code=1`。
- 做法：
  - `loadMenu` 把"是否显示 ssh 主机"存到 ivar；`menuWillOpen:` 只在开启时才调用 `sshConfigFilesNeedUpdate`。
  - 开机启动只在配置值和当前实际状态（`launchAtLoginController.launchAtLogin`）不一致时才设置。
  - 为了可测试，把默认 ssh 配置文件列表抽成一个方法。现在 `parseSSHConfigFile` 和 `sshConfigFilesNeedUpdate` 里各写了一遍，抽出来后测试可以用子类覆盖。
- 注意两个容易引入的回归：
  - 首次打开菜单必须无条件加载一次。配置文件不存在时，`needUpdateFor:` 返回 NO，现在之所以还能显示 "Error parsing config"，是因为 ssh 检查总返回 YES 顺带触发了加载。加了开关后要用一个"已加载过"的标志兜底，否则菜单只剩固定项，没有任何提示。
  - 配置文件（主配置和 alt 配置）从存在变成不存在时也要重新加载，与 `sshConfigFilesNeedUpdate` 对已删除文件的处理保持一致；否则删掉配置后菜单停留在旧内容。
- 回归用例：
  - `false` 时连续打开 3 次，菜单项对象不变；期望值与当前状态相同时 `setLaunchAtLogin:` 不被调用；
  - `true` 时行为不变；
  - 配置文件不存在时首次打开就显示 "Error parsing config"；
  - 加载成功后删除配置文件，再打开菜单时显示错误项。
- 必须和 1.2 一起上线：修完 1.1 后菜单不再每次重新加载，如果 1.2 的异常还在，菜单出错后就会一直是空的。

### 1.2 布尔配置项没有类型检查

- 现状：`launch_at_login` 和 `show_ssh_config_hosts` 直接调用 `boolValue`（`AppDelegate.m:511`、`:531`）。值是 `null`、数组或对象时抛 `unrecognized selector`。实测主机项被全部清空，只剩 4 个固定菜单项，也没有错误提示。
- 做法：仿照现有的 `stringValueForKey:` 新增 `boolValueForKey:inDictionary:defaultValue:`。NSNumber 和 NSString 照旧走 `boolValue`（保留现在字符串 `"true"` / `"false"` 的行为），其他类型返回默认值并打日志。默认值：`show_ssh_config_hosts` 为 YES，`launch_at_login` 为 NO，与现在一致。
- 回归用例：`null`、`[]`、`{}`、`"true"`、`false` 各一组。

### 1.3 ssh config 解析

- 现状：
  - 遇到 `Host =` 或 `Host=` 时别名为空，执行 `servers[nil] = ...` 抛异常（`AppDelegate.m:482-483`，已实测）。Python 版测试实现已经处理了这种情况，ObjC 版没有。
  - 过滤通配符时只认 `*`（`:546`），`Host web?`、`Host !bastion` 会作为可点击的主机出现在菜单里。
- 做法：
  - 别名为空时把 `key` 设为 nil 并跳过，这样后面的 `# shuttle.*` 注释也不会错挂到上一个主机上。
  - 对 ssh 别名（`key`）检查 `*`、`?`、`!`，保留现有对显示名的检查。
- 回归用例：新增一个 fixture，包含 `Host =`、`Host web?`、`Host !bastion foo`。

### 1.4 同名主机 / 分组被吞（按 D2）

- 现状：`buildMenu:addToMenu:` 用名字作为字典的键（`AppDelegate.m:642-661`），后出现的覆盖先出现的。实测两个都叫 `prod` 的主机只显示一个；两个 `Work` 分组只剩其中一个的内容。
- 做法：
  - 叶子收集成数组，按名字稳定排序（`NSSortStable` + `localizedCaseInsensitiveCompare:`）。
  - 同名分组把数组合并，合并时新建数组，不修改 JSON 解析出来的原数组。
  - 排序规则保持不变：分组在前、`[aaa]` 前缀排序、`[---]` 分隔线。
- 行为变化：以前 alt 配置（以及 ssh config）里的同名项会覆盖主配置里的，改完后两个都显示。要写进 CHANGELOG。
- 回归用例：同名叶子、同名分组、分组和分隔线组合。

## 阶段 2：体验与健壮性

### 2.1 配置错误不再强制退出（按 D3）

- 现状：`inTerminal` 值非法、或菜单项数据不完整时，调用 `throwError:...continueOnErrorOption:NO`（`AppDelegate.m:746-751`、`:803-808`），弹窗只有一个 Quit 按钮，点了 Shuttle 就退出（`:964-981`）。
- 做法：改用已有的 `showWarning:additionalInfo:`，然后 `return`。改完后 `throwError:` 没有调用方，一并删除。不引入大小写归一化。

### 2.2 About 窗口泄漏

- 现状：`AboutWindowController.m:23-30` 把 `[super initWithWindow:]` 的结果赋给了 `aboutWindow` 属性，而不是 `self`（静态分析报了这一处），对象强引用自己，永远不会释放。`showAbout:`（`AppDelegate.m:1023-1034`）每次都新建一个，窗口叠在一起。另外 `plistDict` 是非 static 的全局变量（`AboutWindowController.m:21`）。
- 做法：
  - 删掉 `initWithWindow:` 覆盖和 `aboutWindow` 属性，统一用 `self` / `self.window`。已核对 xib 里没有 `aboutWindow` 的 outlet 连接，可以安全删除。
  - `plistDict` 改成在方法里直接取 `[[NSBundle mainBundle] infoDictionary]`。
  - AppDelegate 持有一个实例，重复使用。
  - 可选：显示前调用 `[NSApp activateIgnoringOtherApps:YES]`。
- 验收：`analyze` 不再报 `AboutWindowController.m`；连续点几次 About 只有一个窗口。

### 2.3 导入 / 导出

- 导出（`AppDelegate.m:983-996`）：目标文件已存在时，即使在保存面板里确认了替换，`copyItemAtPath:toPath:` 也一定失败。改为先复制到 `NSItemReplacementDirectory` 临时目录，再用 `replaceItemAtURL:` 替换；默认文件名设为 `shuttle.json`。
- 导入（`AppDelegate.m:918-962`）：替换前先用 `loadJSONDictionaryAtPath:` 校验，不是合法 JSON 就提示并放弃，不覆盖现有配置。
- 验收：手动导出覆盖已有文件成功；导入非法文件时原配置不变。

### 2.4 编辑器命令 + 菜单项 target

- 现状：
  - `editor` 的值被 `stringValueForKey:` 转成了小写（`AppDelegate.m:125`、`:508`）；
  - 判断 `"default"` 用的是子串匹配（`:1001`）；
  - 配置文件路径没有加 shell 引号（`:1007`），路径有空格就会出错；
  - 还在用旧的 `¬_¬` 加 `"(null)"` 拼接载荷（`:1010`）；
  - `buildMenu` 生成的菜单项没有 `setTarget:self`（14fd740 加过，被 a8f3b8a 的回滚一起撤掉了）。
- 做法：
  - editor 读取原始值；`default` 改成不区分大小写的整串比较；
  - 路径用单引号转义；
  - 改用字典载荷 `{cmd, title, name}`；
  - 叶子菜单项和编辑器菜单项都设置 `setTarget:self`；
  - 顺带消除 `analyze` 对 `:1013` 未本地化标题的警告。
- 回归用例：把拼接编辑器命令的逻辑抽成一个纯函数，测试路径中含空格和单引号的情况。

### 2.5 终端启动移出主线程（风险最高，放在本阶段最后）

- 现状：`openHost:` 在主线程上同步调用 TerminalManager。iTerm 冷启动最坏情况要等 AppleScript 里的 3 秒、`usleep` 10×200ms，再加两次 `waitUntilExit`（`TerminalManager.m:314-407`）；iTerm 已运行时也要同步等 osascript 执行完。这期间菜单栏没有响应。
- 做法：TerminalManager 内部建一个串行 dispatch 队列，`executeCommandDirectly:...` 改为异步投递到这个队列（串行保证连续点击按顺序执行）。不改冷启动的判断逻辑和等待参数。
- 手动验收（需要你在本机做）：
  - iTerm 未运行时点主机：只出现一个窗口或 tab，命令正常执行；
  - iTerm 已运行时：tab、new、current 三种模式都正常；
  - 冷启动过程中菜单栏图标仍然可以点。

### 2.6 LaunchAtLoginController 泄漏（仅 D1 选 12.0 时需要）

- 现状：`LSSharedFileListInsertItemURL` 的返回值没有释放（`LaunchAtLoginController.m:136`，静态分析报告），只影响 macOS 12。
- 做法：补上 `CFRelease`。如果 D1 选 13.0，整套旧实现都会删掉，这一步就不用做了。

## 阶段 3：清理（只删不改行为，单独提交）

### 3.1 TerminalManager 死代码

- 删除：`executeCommand:...`（`TerminalManager.m:21-31`）、`executeInTerminal:`（`:33-86`）、`executeInITerm:`（`:88-154`）、`escapeShellCommand:`（`:207-214`），以及头文件里的对应声明。
- 同时删除 AppDelegate 里注释掉的旧调用（`AppDelegate.m:840-845`）。

### 3.2 AppDelegate 死代码与旧系统分支

- 删除 `runScript:handler:parameters:`（`AppDelegate.m:854-907`）。
- 删除 macOS 10.9 以下才用的 `altIcon` 分支（`:85-98`）和 `StatusIconAlt.png` / `StatusIconAlt@2x.png`，同时删掉 `project.pbxproj` 里的引用（两张图各 4 处）。
- `shuttleHostsAlt` 只当局部变量用，从 ivar 改成局部变量。
- 不动 `arrayController`：MainMenu.xib 里有它的 outlet 连接，删掉 ivar 会在启动加载 nib 时触发 KVC 异常。要删得先在 Xcode 里删掉连接。

### 3.3 无用资源与脚本

- 10 个从来没被加载过的 `.scpt`（`Shuttle/apple-scpt/`），需要同时删掉 `project.pbxproj` 里的引用和 `apple-scpt` 分组。
- `Shuttle/apple-scpt-text/`（工程里没有引用）、`apple-scripts/`（编译脚本硬编码了 `~/Git/shuttle`）、`create_applescripts.sh`。
- `Shuttle/es.lproj/MainMenu.xib`：和 Base 版本完全相同，而且工程里没有引用，是个孤立文件。
- `Shuttle/Shuttle.entitlements` 里的 `com.apple.security.temporary-exception.apple-events`：只在开启沙盒时生效，app 没开沙盒。
- 验收：构建后 `Shuttle.app/Contents/Resources` 里不再有 `.scpt`；smoke test 通过。

## 阶段 4：本地化与工程

### 4.1 本地化补全（等所有用户可见文案定稿后再做）

- zh-Hans 缺 7 条："Error parsing config"、"Error parsing alternate config"、"Could not import config"、"Could not export config"、"Invalid menu item configuration"、"The selected item does not contain a complete command definition."、"OK"。另外加上阶段 1、2 新增的文案。es、fr 可选。
- 顺带把 `"About " + 名称` 这类字符串拼接改成格式化字符串（会改变 key，所有语言文件要一起更新）。

### 4.2 Release 构建脚本

- 新增 `scripts/build-release.sh`：Release 配置，输出到 `products/Release/`。
- README 的安装说明改为使用 Release 包。安装到 `/Applications` 仍然由你手动执行。

### 4.3 固定签名（按 D4，可选）

- 现在是临时（ad-hoc）签名，每次重新构建签名都会变，通常需要重新授予控制 iTerm 的自动化权限。
- 做法：在钥匙串里创建一个自签名的代码签名证书，通过环境变量或 xcconfig 指定，不写进仓库。

## 阶段 5：待验证

### 5.1 Terminal.app 冷启动是否多开窗口

- 疑点：`executeInTerminalDirectly:` 在 Terminal 刚启动时就判断 `count of windows = 0`（`TerminalManager.m:515-518`），和 b59983b 修掉的 iTerm 时序竞争是同一类问题。
- 做法：先在 Terminal 未运行时手动复现，确认有问题后再参照 iTerm 的思路修。

## 其他低优先级备忘（来自代码阅读，未实测）

- `parseAltJSON` 只在启动时决定一次：Shuttle 启动后才创建的 `~/.shuttle-alt.json` 要重启才会生效；启动后删掉它，下次重新加载时会显示 "Error parsing alternate config"。
- `~/.shuttle.path` 里写 `~` 开头的路径会读取失败：`loadJSONDictionaryAtPath:` 没有展开 `~`（检查修改时间的代码展开了，两处不一致），编辑、导入、导出也用的是未展开的路径。在 `awakeFromNib` 读取 `.shuttle.path` 时统一展开即可。

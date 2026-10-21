# Contributing / 贡献指南

Thank you for helping with the Simplified Chinese maintenance fork of Reynard. / 感谢协助维护 Reynard 浏览器中文分支。

## Translation contributions / 翻译贡献

- Edit `browser/Reynard/Resources/Localizable.xcstrings` for general UI and `browser/Reynard/Client/Interface/Library/Settings/SettingsLocalizable.xcstrings` for settings.
- Keep `zh-Hans` values meaningful and nonempty; set the state to `translated` only after review.
- Do not change format specifiers such as `%@`, `%d`, `%1$@`, or line-break semantics. Some keys use plural variations.
- Prefer consistent terms: 标签页 (tab), 扩展/插件 (add-on), 阅读模式 (reader), 跟踪防护 (tracking protection).
- Run `python3 tools/tests/check_zh_hans.py` before proposing changes.

## Code / 代码

1. Make small scoped changes and explain the user-visible behavior, compatibility risk and security impact.
2. For download/network issues, include a reproducer (iOS version, install method, expected vs. actual result); never submit private URLs or credentials.
3. Confirm that the Xcode project contains any newly added Swift files and that extensions are preserved when packaging.
4. Link to upstream fixes rather than claiming their commits as independent work.
5. Do not claim builds passed without a corresponding public CI run or reproducible test output.

## Licensing

Respect [GPL-3.0](LICENSE), [Firefox/Gecko licensing](LICENSE.firefox), and the original author's work. Public contributions to the fork are subject to the repository's existing licenses.

## Reporting

GitHub Issues may be disabled in this fork; use a Pull Request for non-sensitive reports, or upstream Issues for upstream-only defects. For vulnerabilities, follow [SECURITY.md](SECURITY.md) and avoid public exploit disclosure.

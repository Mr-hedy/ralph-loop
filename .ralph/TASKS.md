<!-- 参考样板，随 .ralph/ 部署单元 cp -r 到使用者 workspace；可按需裁剪。
     ralph 只识别顶层 `- [ ]` / `- [x]`（正则 `^\s*- \[([ xX])\]`）；子 bullet 是给 agent 读的，不进解析。 -->

- [x] 初始化：确认 .ralph/ 已部署到本 workspace，git init 已完成。

- [ ] 写 hello.txt：内容为一行 "hello ralph"，完成后 commit。
  - 文件路径：hello.txt（workspace 根目录）。
  - 内容严格为 `hello ralph`，无多余空行。
  - 完成后：`git add -A && git commit -m "add hello.txt"`。

- [ ] 在 README.md 末尾追加一行 `<!-- setup complete -->`，完成后 commit。

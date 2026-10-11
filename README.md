# TG WEB Agent Releases

本仓库只放 **编好的 Linux 二进制**，源码不公开。

- 下载：右侧 Releases 里的 `tg-web-agent`
- 版本号见 `VERSION`

一键安装（首次，会编译官方 MTProxy 并写出配置）：

```bash
curl -fsSL https://raw.githubusercontent.com/727263/tg-web-agent-releases/main/install.sh | bash -s -- --hostname proxy.example.com --email you@example.com
```

已安装过再执行同一条命令，只换程序并重启，不改 `config.yaml`：

```bash
curl -fsSL https://raw.githubusercontent.com/727263/tg-web-agent-releases/main/install.sh | bash
```

手动下载：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/727263/tg-web-agent-releases/main/install.sh
curl -fsSL -o tg-web-agent https://github.com/727263/tg-web-agent-releases/releases/latest/download/tg-web-agent
chmod +x install.sh tg-web-agent
sudo bash install.sh --hostname proxy.example.com --email you@example.com
```

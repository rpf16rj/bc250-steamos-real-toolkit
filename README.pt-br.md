# BC-250 SteamOS Real Toolkit

> ⚠️ **Aviso de responsabilidade:** esta ferramenta altera configurações de baixo nível do sistema (bootloader, módulos do kernel, perfis de energia e overclock) em um hardware BC-250 não oficial. Use por sua conta e risco — o autor e os colaboradores não se responsabilizam por qualquer dano, perda de dados ou falha de hardware. Sempre verifique se sua fonte, cabeamento e refrigeração suportam os perfis de overclock antes de aplicá-los, e mantenha backups sempre que possível.

🇺🇸 Prefer English? Read the [README.md](./README.md).

## O que é isso?

Um toolkit amigável e guiado por menus para a placa AMD BC-250 (Cyan Skillfish / GFX1013) rodando o **SteamOS de verdade** — não é um port do CachyOS. Ele reúne ajuste de CPU/GPU, desbloqueio de unidades de computação, controle de sensores/fans e algumas correções feitas pela comunidade em um único script interativo, para você não precisar tocar no bootloader ou compilar nada manualmente.

## Principais Funcionalidades

- Governors de performance de CPU & GPU, com perfis prontos (Padrão → Extremo) ou combinações totalmente personalizadas
- Desbloqueio de Compute Units (CU) — até 40 CUs em tempo real, com persistência após reiniciar
- Alternância de mitigações de CPU (desabilitar/reabilitar)
- Monitoramento de sensores e fans, com controle total de PWM opcional
- Integração com CoolerControl para curvas de fan personalizadas via interface web
- Controle de HDMI-CEC / TV e receiver
- Correções feitas pela comunidade: estados de energia ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800
- Instalação em um clique, atalho de área de trabalho automático, e atualizador embutido — tudo totalmente reversível

## Sistema Compatível

- SteamOS real (testado na versão 3.8.21 beta)
- Placa AMD BC-250
- Acesso root e conexão com a internet

## Instalação Rápida

Abra um terminal na sua máquina SteamOS (Modo Desktop → Konsole) e execute:

```bash
curl -sSL https://raw.githubusercontent.com/rpf16rj/bc250-steamos-real-toolkit/main/start.sh -o start.sh && chmod +x start.sh && sudo ./start.sh
```

É só isso — o script pede `sudo` se necessário, cria um atalho na área de trabalho no primeiro uso, e guia você pelo resto a partir do próprio menu.

## Agradecimentos

Este toolkit se apoia em um ótimo trabalho feito pela comunidade do BC-250. Um agradecimento enorme a:

- [keyboardspecialist](https://github.com/keyboardspecialist) — [bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) (correção ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800, controle HDMI-CEC)
- [Fred78290](https://github.com/Fred78290) — [nct6687d](https://github.com/Fred78290/nct6687d) (driver de controle PWM dos fans)
- [duggasco](https://github.com/duggasco) — [bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock) (patch de kernel para o desbloqueio de 40 CUs)
- [redbeard1083](https://github.com/redbeard1083) — [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit) (configuração de swap / ZRAM→ZSWAP)
- [bc250-collective](https://github.com/bc250-collective) — [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) (governor de CPU)
- [filippor](https://github.com/filippor) — [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (governor de GPU)
- O projeto [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol)

Sem o trabalho deles, nada disso seria possível. 🙏

## Changelog

### 2026-07-11

- Adicionado instalador do driver do Adaptador Xbox Wireless em **Extras**: instala `dkms`, `xone-dkms` e `xone-dongle-firmware` via AUR helper, bloqueia drivers conflitantes (`xpad`, `mt76x2u`) e carrega o `xone` automaticamente.
- Corrigida a atualização do repositório de Correções da Comunidade, que abortava quando um build anterior deixava artefatos locais (ex.: `amdgpu.ko.zst`) no checkout.

### 2026-07-09

- Menu totalmente simplificado e reorganizado: **Install All**, **Install Manual**, **Performance Profiles**, **Revert/Uninstall All** e **Extras** (sensores, CoolerControl, HDMI-CEC), além de acesso rápido a **Verify My Setup**, **Changelog**, **Update Script** e **Help**.
- Adicionado atualizador embutido, criação automática de atalho na área de trabalho no primeiro uso, e as mitigações de CPU + CU Unlock Live agora fazem parte do fluxo de instalação/desinstalação em um clique.
- Adicionado ajuste de Swap/ZRAM→ZSWAP e controle de HDMI-CEC / TV.
- Corrigido um bug que impedia a interface de controle remoto do governor de GPU de funcionar corretamente.

### 2026-07-08

- Adicionado monitoramento de sensores e fans do chip integrado do BC-250, com controle total de PWM opcional.
- Adicionada integração com CoolerControl para curvas de fan personalizadas.
- Adicionado o menu de Correções da Comunidade (estados de energia ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800).
- Diversas correções de confiabilidade na instalação, validadas em hardware real.

### 2026-07-06

- Primeiro lançamento público: Install All / Uninstall All em um clique, CU Unlock Live, perfis de performance, log automático de erros, e reparo automático do keyring do pacman.

## Licença

Estes scripts são baseados em trabalho da comunidade para o BC-250. Use por sua conta e risco.

## Comunidade

Tem dúvidas, encontrou algum problema, ou só quer trocar uma ideia sobre o BC-250? Entre no nosso [Discord](https://discord.com/channels/1315924807128449065/).

## Apoie o projeto

Se este toolkit te economizou tempo, considere me pagar um café: [buymeacoffee.com/rpf16rj](https://buymeacoffee.com/rpf16rj) ☕

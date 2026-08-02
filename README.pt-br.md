# BC-250 SteamOS Real Toolkit

> ⚠️ **Aviso de responsabilidade:** esta ferramenta altera configurações de baixo nível do sistema (bootloader, módulos do kernel, perfis de energia e overclock) em um hardware BC-250 não oficial. Use por sua conta e risco — o autor e os colaboradores não se responsabilizam por qualquer dano, perda de dados ou falha de hardware. Sempre verifique se sua fonte, cabeamento e refrigeração suportam os perfis de overclock antes de aplicá-los, e mantenha backups sempre que possível.

> ⚠️ **Atualizações do SteamOS:** uma atualização pode substituir o kernel, módulos, headers, configuração de boot ou serviços instalados. Depois de **toda atualização do SteamOS**, consulte o status do toolkit e esteja preparado para reinstalar os componentes afetados. Isso é especialmente importante se o canal **Beta** estiver ativo. Se ocorrer um erro, o toolkit salva um log de diagnóstico na sua pasta pessoal e também o copia para a Área de Trabalho quando possível. O atalho da Área de Trabalho mantém o terminal aberto depois que o script termina, permitindo visualizar o erro.

> 🔄 **Já instalou e só quer atualizar?** Depois de baixar uma [versão mais nova](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) do toolkit, não precisa desinstalar nada antes — basta rodar **Install All** de novo no menu principal. Ele reaplica e atualiza cada componente no lugar (correções, drivers, serviços, perfis), pulando o que já está atualizado.

> ⚡ **Consumo de energia com 8 núcleos de CPU / 40 CUs ativos:** Rodar os 8 núcleos de CPU (Desbloqueio de Núcleos de CPU) junto com as 40 unidades de computação da GPU consome bem mais energia da fonte do que a configuração de fábrica (6c/12t + 32 CUs). Se você tiver travamentos, reinicializações ou desligamentos aleatórios sob carga nessa combinação, sua fonte pode estar subdimensionada — tente um perfil de undervolting antes de suspeitar de defeito de hardware. O perfil de performance **Mild (undervolt)** (CPU 3.5 GHz / GPU 1600 MHz, com undervolt) foi testado estável usando uma fonte de servidor HP de 460 W.

🇺🇸 Prefer English? Read the [README.md](./README.md).

## O que é isso?

Um toolkit amigável e guiado por menus para a placa AMD BC-250 (Cyan Skillfish / GFX1013) rodando o **SteamOS de verdade** — não é um port do CachyOS. Ele reúne ajuste de CPU/GPU, desbloqueio de unidades de computação, controle de sensores/fans e algumas correções feitas pela comunidade em um único script interativo, para você não precisar tocar no bootloader ou compilar nada manualmente.

## Principais Funcionalidades

- Governors de performance de CPU & GPU, com perfis prontos (Padrão → Extremo) ou combinações totalmente personalizadas
- Desbloqueio de Compute Units (CU) — até 40 CUs em tempo real, com persistência após reiniciar
- Desbloqueio de Núcleos de CPU — ⚠ experimental, 6c/12t → 8c/16t via escrita na mailbox da SMU, com serviço de reaplicação no boot
- RAM/VRAM Split — UMA_SIZE=512MB dinâmico + teto do ttm.pages_limit elevado, libera quase toda a RAM de 16GB em idle
- Alternância de mitigações de CPU (desabilitar/reabilitar)
- Monitoramento de sensores e fans, com controle total de PWM opcional
- Integração com CoolerControl para curvas de fan personalizadas via interface web
- Plugin Decky Toolkit SteamOS Control pré-compilado, com controles automático/manual/gerenciado da Pump Fan, perfis de quatro pontos e controles opcionais da LED bar
- Controle de HDMI-CEC / TV e receiver
- Correções feitas pela comunidade: estados de energia ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800
- Instalação em um clique, atalho de área de trabalho automático, e lançamentos versionados com changelog — tudo totalmente reversível

## Sistema Compatível

- SteamOS real (testado na versão 3.8.21 beta)
- Placa AMD BC-250
- Acesso root e conexão com a internet

## Instalação Rápida

1. Baixe o zip da [**última release**](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) na sua máquina SteamOS (Modo Desktop, ou `Download` na página de releases).
2. Extraia, abra um terminal na pasta extraída (Modo Desktop → Konsole), e execute:

```bash
sudo ./start.sh
```

É só isso — o script pede `sudo` se necessário, cria um atalho na área de trabalho no primeiro uso, e guia você pelo resto a partir do próprio menu.

Para atualizar depois, baixe o zip da release mais nova, extraia por cima da pasta antiga (ou em uma pasta nova), e rode o `start.sh` de novo — veja o aviso acima sobre o `Install All`.

## Agradecimentos

Este toolkit se apoia em um ótimo trabalho feito pela comunidade do BC-250. Um agradecimento enorme a:

- [keyboardspecialist](https://github.com/keyboardspecialist) — [bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) (correção ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800, controle HDMI-CEC)
- [Fred78290](https://github.com/Fred78290) — [nct6687d](https://github.com/Fred78290/nct6687d) (driver de controle PWM dos fans)
- [duggasco](https://github.com/duggasco) — [bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock) (patch de kernel para o desbloqueio de 40 CUs)
- [rw-r-r-0644](https://github.com/rw-r-r-0644) — [bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock) (desbloqueio de núcleos de CPU, 6c/12t → 8c/16t)
- [mendesrr](https://github.com/mendesrr) — [bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c) (tabelas ACPI C-/P-state, compatíveis com 6c e 8c)
- [fanoush](https://github.com/fanoush) — [bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (ferramenta CMOS de RAM/VRAM split)
- [redbeard1083](https://github.com/redbeard1083) — [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit) (configuração de swap / ZRAM→ZSWAP)
- [bc250-collective](https://github.com/bc250-collective) — [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) (governor de CPU)
- [filippor](https://github.com/filippor) — [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (governor de GPU)
- O projeto [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol)

Sem o trabalho deles, nada disso seria possível. 🙏

## Changelog

Veja o [CHANGELOG.pt-br.md](./CHANGELOG.pt-br.md) para o histórico completo de versões (ou [CHANGELOG.md](./CHANGELOG.md) em inglês).

## Licença

Estes scripts são baseados em trabalho da comunidade para o BC-250. Use por sua conta e risco.

## Comunidade

Tem dúvidas, encontrou algum problema, ou só quer trocar uma ideia sobre o BC-250? Entre no nosso [Discord](https://discord.com/channels/1315924807128449065/).

## Apoie o projeto

Se este toolkit te economizou tempo, considere me pagar um café: [buymeacoffee.com/rpf16rj](https://buymeacoffee.com/rpf16rj) ☕

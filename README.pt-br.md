# BC-250 SteamOS Real Toolkit

> ⚠️ **Aviso de responsabilidade:** esta ferramenta altera configurações de baixo nível do sistema (bootloader, módulos do kernel, perfis de energia e overclock) em um hardware BC-250 não oficial. Use por sua conta e risco — o autor e os colaboradores não se responsabilizam por qualquer dano, perda de dados ou falha de hardware. Sempre verifique se sua fonte, cabeamento e refrigeração suportam os perfis de overclock antes de aplicá-los, e mantenha backups sempre que possível.

> ⚠️ **Atualizações do SteamOS:** uma atualização pode substituir o kernel, módulos, headers, configuração de boot ou serviços instalados. Depois de **toda atualização do SteamOS**, consulte o status do toolkit e esteja preparado para reinstalar os componentes afetados. Isso é especialmente importante se o canal **Beta** estiver ativo. Se ocorrer um erro, o toolkit salva um log de diagnóstico na sua pasta pessoal e também o copia para a Área de Trabalho quando possível. O atalho da Área de Trabalho mantém o terminal aberto depois que o script termina, permitindo visualizar o erro.

> 🔄 **Já instalou e só quer atualizar?** Depois de baixar uma [versão mais nova](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) do toolkit, não precisa desinstalar nada antes — basta rodar **Install All** de novo no menu principal. Ele reaplica e atualiza cada componente no lugar (correções, drivers, serviços, perfis), pulando o que já está atualizado.

> ⚡ **Consumo de energia com 8 núcleos de CPU / 40 CUs ativos:** Rodar os 8 núcleos de CPU (Desbloqueio de Núcleos de CPU) junto com as 40 unidades de computação da GPU consome bem mais energia da fonte do que a configuração de fábrica (6c/12t + 32 CUs). Se você tiver travamentos, reinicializações ou desligamentos aleatórios sob carga nessa combinação, sua fonte pode estar subdimensionada — tente um perfil de undervolting antes de suspeitar de defeito de hardware. O perfil de performance **Mild (undervolt)** (CPU 3.5 GHz / GPU 1600 MHz, com undervolt) foi testado estável usando uma fonte de servidor HP de 460 W.

🇺🇸 Prefer English? Read the [README.md](./README.md).

---

## O que é isso?

Um toolkit amigável e guiado por menus para a placa AMD BC-250 (Cyan Skillfish / GFX1013) rodando o **SteamOS de verdade** — não é um port do CachyOS. Ele reúne ajuste de CPU/GPU, desbloqueio de unidades de computação, controle de sensores/fans, correções de display e áudio, e patches da comunidade em um único script interativo, para você não precisar tocar no bootloader ou compilar nada manualmente.

---

## Funcionalidades

### Performance & Ajustes

- **Governors de performance de CPU & GPU** — perfis prontos (Padrão → Extremo) ou combinações totalmente personalizadas
- **Desbloqueio de Compute Units (CU)** — até 40 CUs em tempo real, com persistência após reiniciar
- **Desbloqueio de Núcleos de CPU** — ⚠ experimental, 6c/12t → 8c/16t via escrita na mailbox da SMU, com serviço de reaplicação no boot
- **RAM/VRAM Split** — UMA_SIZE=512MB dinâmico + teto do ttm.pages_limit elevado, libera quase toda a RAM de 16GB em idle
- **Alternância de mitigações de CPU** — desabilitar/reabilitar mitigações Spectre/Meltdown para performance
- **Swap & ZSWAP** — swapfile configurável + ZSWAP comprimido com lz4 substituindo ZRAM

### Display & Áudio

- **DP-HDMI YCbCr 4:4:4 Deep Color + HDMI 2.1 FRL** — força YCbCr 4:4:4 com deep color 10/12 bits em adaptadores PCON DP-HDMI (ex. Ugreen CH7218). Habilita HDMI 2.1 FRL a 48 Gbps para **1440p@120 12-bit** e **4K@60 12-bit**. Veja [docs/dp-hdmi-ycbcr444-frl.md](./docs/dp-hdmi-ycbcr444-frl.md) para tabelas de banda.
- **Correção de clock de áudio/vídeo do DisplayPort** — corrige timing de áudio/vídeo DP e desabilita spread spectrum
- **Codificação AC-3 Surround via HDMI** — Dolby Digital 5.1 por HDMI/DP via eARC, codificação nativa a52 sem latência
- **Controle de HDMI-CEC / TV** — controle sua TV ou receiver via HDMI-CEC
- **HPD debounce** — previne eventos espúrios de hot-plug detect quando a TV é ligada/desligada

### Drivers & Correções

- **Correção da fila de compute GFX1013** — compute assíncrono + Mesa/RADV patchadas com suporte a mesh/task shaders e FSR4 V3
- **Correção de estados de energia ACPI** — tabelas ACPI C-/P-state corretas (compatíveis com 6c e 8c)
- **Driver WiFi/BT AIC8800** — para dongles USB WiFi/BT AIC8800D80
- **Firmware BE200 Wi-Fi 7** — para placas PCIe Intel BE200/BE201 sem ucode
- **Fix do PS Button do DS5 Bridge** — chord combos do DualSense via hid-playstation.ko patchado
- **DS5 Chord Config** — patch VDF para configuração de chords com QAM habilitado

### Monitoramento & Controle

- **Monitoramento de sensores e fans** — com controle total de PWM opcional
- **Integração com CoolerControl** — curvas de fan personalizadas via interface web
- **Plugin Decky pré-compilado** — Toolkit SteamOS Control com controles de Pump Fan, perfis de quatro pontos e controles opcionais da LED bar
- **CU/WGP Live Manager** — habilitar/desabilitar CU/WGP em tempo real sem reiniciar

### Qualidade de Vida

- **Instalação em um clique** — atalho de área de trabalho automático, lançamentos versionados com changelog
- **Tudo totalmente reversível** — reverte componentes individuais ou tudo de uma vez
- **Persistência após atualizações do SteamOS** — rastreia componentes instalados e reaplica após atualizações do sistema

## Sistema Compatível

- SteamOS real (testado na versão 3.8.21 beta e 3.10 com kernel 7.2)
- Placa AMD BC-250
- Acesso root e conexão com a internet

> **Atualizando para SteamOS 3.10 / kernel 7.2:** ative o Modo Desenvolvedor (Configurações → Sistema → Modo Desenvolvedor), depois ative Canais de Atualização Avançados e troque o canal para **Main**. Após a atualização, rode Install All de novo para reaplicar os patches do toolkit no novo kernel.

## Instalação Rápida

1. Baixe o zip na página da [**última release**](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) na sua máquina SteamOS (Modo Desktop).
2. Extraia, abra um terminal na pasta extraída (Modo Desktop → Konsole), e execute:

```bash
sudo ./start.sh
```

É só isso — o script pede `sudo` se necessário, cria um atalho na área de trabalho no primeiro uso, e guia você pelo resto a partir do próprio menu.

Para atualizar depois, baixe o zip da release mais nova, extraia por cima da pasta antiga (ou em uma pasta nova), e rode o `start.sh` de novo — veja o aviso acima sobre o `Install All`.

---

## Troubleshooting

### Depois de uma atualização do SteamOS, algo parou de funcionar

Atualizações do SteamOS podem substituir o kernel, módulos e configuração de boot. Rode **Install All** no menu do toolkit para reaplicar todos os patches. Se a versão do kernel mudou, o Combined Fix vai recompilar o `amdgpu.ko` para o novo kernel automaticamente.

### Sem vídeo após reiniciar (Combined Fix)

O toolkit inclui guardas de vermagic e ABI que recusam instalar um módulo incompatível. Se o build falhar, o `amdgpu.ko` original permanece intacto e seu display deve funcionar. Se ainda assim não houver vídeo:

1. Inicie no Modo Desktop (ou conecte via SSH)
2. Rode `sudo ./start.sh` → Revert Combined Fix
3. Reinicie

### Temperatura da GPU aparece como 0

No kernel 7.x com 8 núcleos desbloqueados e BIOS stock (sem patch de SMU), adicione `amdgpu.cs_legacy_8core_metrics=1` ao GRUB. O toolkit pergunta isso durante a instalação.

### Adaptador DP-HDMI: sem deep color / banding de cor

1. Verifique se o Combined Fix está instalado (o patch está sempre ativo em todo build)
2. Verifique se `/etc/modprobe.d/amdgpu-ycbcr444.conf` existe com `force_ycbcr444=1 force_min_bpc=10 dcfeaturemask=0x402`
3. Reinicie e verifique: `sudo dmesg | grep -iE "FRL PCON|frl_bw|CH7218"`
4. Você deve ver `frl_bw=48000000` — se `frl_bw=0`, o FRL feature mask ou o quirk do PCON não está ativo
5. Veja [docs/dp-hdmi-ycbcr444-frl.md](./docs/dp-hdmi-ycbcr444-frl.md) para tabelas completas de banda

### DP-HDMI: não consigo 4K@120 com 4:4:4

Isso é uma limitação de hardware. O link DisplayPort 1.4 do BC-250 fornece 25.14 Gbps (HBR3, 4 lanes). 4K@120 10-bit 4:4:4 requer ~35.6 Gbps — excedendo a capacidade do DP 1.4. Use 4K@60 12-bit 4:4:4, 1440p@120 12-bit 4:4:4, ou 4K@120 com YCbCr 4:2:0.

### Travamentos ou reinicializações aleatórias sob carga

Se estiver rodando 8 núcleos + 40 CUs, sua fonte pode estar subdimensionada. Tente o perfil **Mild (undervolt)** primeiro. Se os travamentos persistirem, reverta para 6c/12t + 32 CUs e teste a estabilidade.

### Build falha após atualização do SteamOS

Rode `sudo ./ensure-build-prereqs.sh` para restaurar headers removidos e dependências de build. O toolkit faz isso automaticamente durante o Install All, mas rodar manualmente pode ajudar a diagnosticar problemas.

---

## Agradecimentos

Este toolkit se apoia em um ótimo trabalho feito pela comunidade do BC-250. Um agradecimento enorme a:

- [keyboardspecialist](https://github.com/keyboardspecialist) — [bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) (correção ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800, controle HDMI-CEC)
- [DryhoppedIPA](https://github.com/DryhoppedIPA) — [bc250-gfx1013-fix](https://github.com/DryhoppedIPA/bc250-gfx1013-fix) (patches de kernel + Mesa/RADV para a fila de compute GFX1013)
- [MastaG](https://github.com/MastaG) — [linux-cachyos-bc250](https://github.com/MastaG/linux-cachyos-bc250) (patches atualizados de Mesa/RADV: mesh/task shaders, compute queue, promoção GFX10.3)
- [lonewolf0622](https://github.com/lonewolf0622) — [BC250-Native-Mesh-Shaders-](https://github.com/lonewolf0622/BC250-Native-Mesh-Shaders-) (patch de mesh shaders nativo sem spoofing de GFX10.3)
- [dmorazasanchez](https://github.com/dmorazasanchez) — [bc250-fsr4](https://github.com/dmorazasanchez/bc250-fsr4) (otimização FSR4 V3 deferred SDot hybrid)
- [Fred78290](https://github.com/Fred78290) — [nct6687d](https://github.com/Fred78290/nct6687d) (driver de controle PWM dos fans)
- [duggasco](https://github.com/duggasco) — [bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock) (patch de kernel para o desbloqueio de 40 CUs)
- [rw-r-r-0644](https://github.com/rw-r-r-0644) — [bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock) (desbloqueio de núcleos de CPU, 6c/12t → 8c/16t)
- [mendesrr](https://github.com/mendesrr) — [bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c) (tabelas ACPI C-/P-state, compatíveis com 6c e 8c)
- [fanoush](https://github.com/fanoush) — [bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (ferramenta CMOS de RAM/VRAM split)
- [redbeard1083](https://github.com/redbeard1083) — [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit) (configuração de swap / ZRAM→ZSWAP)
- [bc250-collective](https://github.com/bc250-collective) — [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) (governor de CPU)
- [filippor](https://github.com/filippor) — [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (governor de GPU)
- [kungaa](https://github.com/kungaa) — [DS5-Linux-Bridge](https://github.com/kungaa/DS5-Linux-Bridge/) (inspiração para o fix do PS Button do DS5 Bridge)
- O projeto [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol)

Sem o trabalho deles, nada disso seria possível. 🙏

---

## Changelog

Veja o [CHANGELOG.pt-br.md](./CHANGELOG.pt-br.md) para o histórico completo de versões (ou [CHANGELOG.md](./CHANGELOG.md) em inglês).

---

## Licença

Estes scripts são baseados em trabalho da comunidade para o BC-250. Use por sua conta e risco.

---

## Comunidade

Tem dúvidas, encontrou algum problema, ou só quer trocar uma ideia sobre o BC-250? Entre no nosso [Discord](https://discord.com/channels/1315924807128449065/).

---

## Apoie o Projeto

Se este toolkit te economizou tempo, te ajudou a tirar o máximo do seu BC-250, ou simplesmente facilitou sua vida, considere apoiar o desenvolvimento contínuo:

### ☕ Buy Me a Coffee

[**buymeacoffee.com/rpf16rj**](https://buymeacoffee.com/rpf16rj)

Seu apoio ajuda a cobrir:

- **Custos de hardware** — adaptadores, dongles e equipamentos de teste para desenvolvimento contínuo
- **Tempo investido** — engenharia reversa de quirks de PCON, debugging de patches de kernel, testes em diferentes configurações
- **Infraestrutura** — CI/CD, hospedagem de releases e documentação

Cada contribuição — grande ou pequena — financia diretamente a próxima feature, correção ou atualização de compatibilidade. Obrigado! 🙏

### Outras Formas de Ajudar

- ⭐ **Dê uma estrela no repo** — ajuda outros a descobrirem o toolkit
- 🐛 **Reporte bugs** — abra uma issue com logs de diagnóstico e detalhes do sistema
- 💬 **Compartilhe seu setup** — deixe a comunidade saber o que funciona (e o que não funciona)
- 🔀 **Contribua** — PRs são bem-vindos para novas correções, drivers ou melhorias

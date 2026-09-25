# BC-250 SteamOS Real Toolkit

> 🧪 **Versão do SteamOS exigida:** este toolkit acompanha apenas o canal **Beta/Preview** mais recente do SteamOS — atualmente o kernel `7.2.4-valve1-1-neptune-72`. Ele **não é compatível com o SteamOS 3.8 estável**: os patches de kernel são específicos de versão e não compilam nem instalam em kernels mais antigos. Confirme que seu sistema está no canal Beta/Preview antes de instalar.

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

- **DCN201 DSC + HDMI 2.1 PCON** — habilita Display Stream Compression (DSC) no núcleo de display DCN 2.0.1 do BC-250 conectando motores DSC compatíveis com DCN200, e anuncia suporte a HDMI 2.1 FRL PCON para bridges DP-HDMI (ex. Ugreen CH7218). Substitui os patches anteriores de YCbCr 4:4:4 / VRR / ALLM / FRL hot-plug, que não são mais necessários. Baseado na investigação de registradores DCN/DSC por [alex-reid](https://gist.github.com/alex-reid/b55328c246ade7baef8566fb2cadea9b).
- **Correção de artefatos/sem imagem em 4K120 via PCON** — limita a profundidade de cor de saída ao que cabe no orçamento FRL anunciado pela TV (o PCON decodifica DSC e re-encoda FRL descomprimido); corrige o 4K120 4:4:4 falhando em cold boot ou boot direto no Game Mode quando nada persistiu `max_bpc`
- **Correção de clock de áudio/vídeo do DisplayPort** — corrige timing de áudio/vídeo DP e desabilita spread spectrum
- **Codificação AC-3 Surround via HDMI** — Dolby Digital 5.1 por HDMI/DP via eARC, codificação nativa a52 sem latência
- **Controle de HDMI-CEC / TV** — controle sua TV ou receiver via HDMI-CEC
- **HPD debounce** — previne eventos espúrios de hot-plug detect quando a TV é ligada/desligada

### Drivers & Correções

- **Correção da fila de compute GFX1013** — compute assíncrono + Mesa/RADV patchadas com suporte a mesh/task shaders e FSR4 V3
- **Correção de estados de energia ACPI** — tabelas ACPI C-/P-state corretas (compatíveis com 6c e 8c)
- **Drivers WiFi/BT AIC8800** — suporte atual ao AIC8800D80 e perfil legacy-MCU1 explícito para dongles WiFi AIC8800DC/DW mais antigos
- **Firmware BE200 Wi-Fi 7** — para placas PCIe Intel BE200/BE201 sem ucode
- **Fix do PS Button do DS5 Bridge** — chord combos do DualSense via hid-playstation.ko patchado
- **DS5 Chord Config** — patch VDF para configuração de chords com QAM habilitado
- **Driver VA-API de vídeo** — encode H.264/HEVC para Sunshine/Steam Link/FFmpeg **mais** decode bit-exact de H.264/HEVC (incl. HEVC Main10) para mpv/FFmpeg `--hwdec=vaapi`, via compute shaders Vulkan + CPU wavefront multi-thread (o bloco VCN do BC-250 vem desativado de fábrica), instalado em `/var/lib/bc250` para sobreviver a updates do SteamOS

### Monitoramento & Controle

- **Monitoramento de sensores e fans** — com controle total de PWM opcional
- **Integração com CoolerControl** — curvas de fan personalizadas via interface web
- **Suporte OpenLinkHub** — controle opcional do Corsair iCUE LINK Hub (RGB, fans, AIO) via interface web
- **Plugin Decky pré-compilado** — Toolkit SteamOS Control com controles de Pump Fan, perfis de quatro pontos e controles opcionais da LED bar
- **CU/WGP Live Manager** — habilitar/desabilitar CU/WGP em tempo real sem reiniciar

### Qualidade de Vida

- **Instalação em um clique** — atalho de área de trabalho automático, lançamentos versionados com changelog
- **Tudo totalmente reversível** — reverte componentes individuais ou tudo de uma vez
- **Persistência após atualizações do SteamOS** — rastreia componentes instalados e reaplica após atualizações do sistema

## Sistema Compatível

- SteamOS real no canal **Beta/Preview** — kernel `7.2.x` (`linux-neptune-72`; testado no SteamOS 3.10)
- Placa AMD BC-250
- Acesso root e conexão com a internet

> **O SteamOS 3.8 estável vem com kernel 6.18 — as instalações dependentes de kernel são bloqueadas nele.** Se o toolkit mostrar mensagem de kernel incompatível, atualize primeiro (abaixo).

## Atualizando o SteamOS para o kernel 7.2

Os patches de kernel do toolkit são feitos para a árvore `linux-neptune-72` da Valve (kernel `7.2.x`), que o SteamOS entrega no canal **Beta/Preview**. Se você está no estável (`6.18.x`), troque de canal e atualize:

**Modo Game:**
`Configurações → Sistema → Canal de Atualização do Sistema` → selecione **Preview** (ou **Beta**) → `Verificar atualizações` → `Aplicar` → reinicie.

**Modo Desktop (Konsole):**

```bash
sudo steamos-select-branch preview   # ou: beta
sudo steamos-update                  # baixa e prepara a atualização
# reinicie, depois verifique:
uname -r   # deve mostrar 7.2.x-...-neptune-72-...
```

Depois de atualizar, rode **Install All** de novo — cada componente se reaplica para o novo kernel.

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

> 💡 **Instalação rápida:** quando existe um `amdgpu.ko`/Mesa pré-compilado publicado que corresponde exatamente ao seu kernel e aos patches escolhidos, o toolkit baixa e instala (checksum + vermagic/ABI verificados) em vez de compilar — minutos viram segundos. Se nada combinar, cai para a compilação local automaticamente.

### Sem vídeo após reiniciar (Combined Fix)

O toolkit inclui guardas de vermagic e ABI que recusam instalar um módulo incompatível. Se o build falhar, o `amdgpu.ko` original permanece intacto e seu display deve funcionar. Se ainda assim não houver vídeo, escolha uma entrada de recovery no menu do GRUB (mostrado automaticamente depois que o toolkit é instalado): **"pre-install kernel+initramfs"** bota com o snapshot dos drivers originais salvo antes do install, ou **"HDMI21-DSC OFF"** desliga o patch DSC/PCON. Num sistema que ainda bota você também pode:

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

### Apps Flatpak (Moonlight) não enxergam o driver VA-API

Sandboxes Flatpak não herdam o `/etc/environment.d`, e alguns apps — incluindo o Moonlight — explicitamente fazem **unset** de `LIBVA_DRIVER_NAME`/`LIBVA_DRIVERS_PATH` no manifest. Dê um override por usuário pro app:

```bash
flatpak override --user com.moonlight_stream.Moonlight \
  --env=LIBVA_DRIVER_NAME=bc250 \
  --env=LIBVA_DRIVERS_PATH=/var/lib/bc250/dri \
  --env=BC250_SHADER_DIR=/var/lib/bc250/shaders \
  --filesystem=/var/lib/bc250:ro
```

Reinicie o app depois. Para desfazer: `flatpak override --user --reset com.moonlight_stream.Moonlight`. O mesmo padrão serve pra qualquer Flatpak que deva usar o driver.

> ⚠️ **Cliente de streaming (Moonlight): mantenha decode por software.** O decoder VLD do bc250 é uma implementação CPU-wavefront bit-exact — medido ~30 fps vs ~510 fps do decoder por software do FFmpeg a 1080p60 HEVC no BC-250. Se o Moonlight mostrar ~2 fps e "network drops" com VAAPI, é a fila de decode transbordando, não a rede — volte o video decoder pra Software. O ganho do driver está no **encode** do lado host (~86 fps HEVC 1080p medido); o decode serve pra apps que exigem `hwdec=vaapi` especificamente.

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

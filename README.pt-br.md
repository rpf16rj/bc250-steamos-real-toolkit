# BC-250 SteamOS Real Toolkit

> ⚠️ **Aviso de responsabilidade:** esta ferramenta altera configurações de baixo nível do sistema (bootloader, módulos do kernel, perfis de energia e overclock) em um hardware BC-250 não oficial. Use por sua conta e risco — o autor e os colaboradores não se responsabilizam por qualquer dano, perda de dados ou falha de hardware. Sempre verifique se sua fonte, cabeamento e refrigeração suportam os perfis de overclock antes de aplicá-los, e mantenha backups sempre que possível.

> ⚠️ **Atualizações do SteamOS:** uma atualização pode substituir o kernel, módulos, headers, configuração de boot ou serviços instalados. Depois de **toda atualização do SteamOS**, consulte o status do toolkit e esteja preparado para reinstalar os componentes afetados. Isso é especialmente importante se o canal **Beta** estiver ativo. Se ocorrer um erro, o toolkit salva um log de diagnóstico na sua pasta pessoal e também o copia para a Área de Trabalho quando possível. O atalho da Área de Trabalho mantém o terminal aberto depois que o script termina, permitindo visualizar o erro.

> 🔄 **Já instalou e só quer atualizar?** Depois de baixar uma versão mais nova do toolkit, não precisa desinstalar nada antes — basta rodar **Install All** de novo no menu principal. Ele reaplica e atualiza cada componente no lugar (correções, drivers, serviços, perfis), pulando o que já está atualizado.

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
- [rw-r-r-0644](https://github.com/rw-r-r-0644) — [bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock) (desbloqueio de núcleos de CPU, 6c/12t → 8c/16t)
- [mendesrr](https://github.com/mendesrr) — [bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c) (tabelas ACPI C-/P-state, compatíveis com 6c e 8c)
- [fanoush](https://github.com/fanoush) — [bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (ferramenta CMOS de RAM/VRAM split)
- [redbeard1083](https://github.com/redbeard1083) — [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit) (configuração de swap / ZRAM→ZSWAP)
- [bc250-collective](https://github.com/bc250-collective) — [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) (governor de CPU)
- [filippor](https://github.com/filippor) — [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (governor de GPU)
- O projeto [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol)

Sem o trabalho deles, nada disso seria possível. 🙏

## Changelog

### 2026-07-30

- **Adicionado:** `Desbloqueio de Núcleos de CPU` em `Install Manual` (`9`/`9R`) e em `Install All`/`Revert All`. Traz vendorizado o [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock), que escreve a máscara de presença de núcleos da BC-250 via mensagem na mailbox da SMU para habilitar os 2 núcleos de CPU desabilitados (6c/12t → 8c/16t). Nenhuma adaptação específica do SteamOS foi necessária — o script upstream só acessa o espaço de configuração PCI e o serviço já existente do governor de GPU. Como a escrita é volátil após um power-off frio, a instalação cria um serviço systemd de boot (`bc250-core-unlock.service`) que reaplica a escrita a cada inicialização; o status agora mostra a contagem atual de núcleos/threads. ⚠ Experimental — veja `external/bc250-core-unlock/README.md` para as ressalvas (possível binning de silício, bug de leitura de clock da GPU).
- **Alterado:** `Install ACPI Fix` agora busca as tabelas SSDT-CST/SSDT-PST do [mendesrr/bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c) em vez das do bc250-collective, pois a comunidade reportou que as tabelas originais (só 6c) apresentam problemas após desbloquear os 2 núcleos extras. Instalações existentes são atualizadas automaticamente na próxima execução da correção ACPI. O `Desbloqueio de Núcleos de CPU` agora instala/atualiza essa correção ACPI de forma transparente na mesma execução, sem confirmação extra, garantindo que as duas correções sempre andem juntas.
- **Alterado:** `external/bc250-steamos/bc250-audio-fix` foi revendorizado a partir do upstream [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos), que agora também corrige o `cyan_skillfish_ppt.c` para consultar o clock GFX diretamente via SMU e adiciona leitura de utilização da GPU (`bc250-cyan-skillfish-gfxclk.patch`, `bc250-cyan-skillfish-gpu-telemetry.patch`) — a correção reportada pela comunidade para as métricas de clock/carga da GPU ficarem incorretas após desbloquear os 2 núcleos extras. O `Install DP Audio/Video Fix` (Install Manual `7`) aplica isso junto com a correção de clock do DisplayPort já existente; não é encadeado automaticamente no `Desbloqueio de Núcleos de CPU` por reconstruir um módulo de kernel, mas o `Install All` já executa essa correção antes da etapa de desbloqueio de núcleos. Também foi vendorizado o script `fetch-steamos-package.sh` do upstream (descoberta multi-canal de pacotes do SteamOS), e corrigido um falso-erro no workaround de SIGPIPE deste toolkit, já que o upstream corrigiu esse bug de forma independente.
- **Adicionado:** `RAM/VRAM Split` em `Install Manual` (`10`/`10R`) e em `Install All`/`Revert All`. Traz vendorizado o [fanoush/bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (compilado localmente a partir do código-fonte na instalação) para escrever `UMA_SIZE=512` na CMOS com bateria da BC-250 — a BIOS de fábrica reserva permanentemente 8192MB (split 8GB/8GB) para VRAM, e 512MB é o piso mínimo documentado, liberando quase toda a RAM de 16GB em idle. Também eleva o teto dinâmico de VRAM do kernel via `ttm.pages_limit` no GRUB (~12GB), já que o teto padrão com piso de 512MB pode ser baixo demais para jogos que pedem 8GB+ de VRAM. Não precisa de BIOS modificada; o status agora mostra o `UMA_SIZE` atual. O revert restaura o split de fábrica de 8192MB e remove o ajuste do GRUB.
- **Corrigido:** o `nano` perdia a navegação por setas ao editar o config de CPU/GPU (menu Performance `F`/`E`) — o redirecionamento `exec > >(tee ...) 2>&1` do log do toolkit deixava o stdout do `nano` como um pipe em vez do terminal real, quebrando o endereçamento de teclado/cursor do ncurses. Os dois editores agora falam diretamente com `/dev/tty`.

### 2026-07-26

- **Corrigido:** O bootstrap standalone one-click agora corrige a propriedade de `~/.bc250-toolkit` antes de clonar como usuário desktop, evitando `could not create work tree dir: Permission denied` após execuções anteriores como root.
- **Corrigido:** As autoatualizações Git são executadas como usuário desktop e primeiro corrigem a propriedade do checkout, evitando `dubious ownership`, `.git/FETCH_HEAD: Permission denied` e pedidos de senha da IDE causados por arquivos do repositório pertencentes ao root.
- **Corrigido:** A ativação runtime do ZSWAP agora persiste após reiniciar por meio de uma regra systemd-tmpfiles em kernels SteamOS que ignoram `zswap.enabled=1`; o status também diferencia ZSWAP configurado, porém inativo.

### 2026-07-23

- **Adicionado:** A opção `Z` em `Extras` instala o plugin Decky Toolkit SteamOS Control pré-compilado. Ele instala automaticamente o Decky Loader stable quando necessário, copia o artefato incluído e reinicia o loader sem Node.js, pnpm ou build local.
- **Adicionado:** Controles automático, manual e por curva gerenciada de quatro pontos para a Pump Fan no canal NCT sensor/PWM da BC-250, além de controles opcionais de efeitos da LED bar quando `steamos-led.service` estiver presente.
- **Adicionado:** Persistência após atualizações do SteamOS para a configuração de fan e o serviço de fan gerenciado do Toolkit SteamOS Control.
- **Melhorado:** A interface Decky separa as visualizações de Cooler e LED bar, preserva alterações não salvas nos sliders durante o polling de status e desabilita os controles da Pump Fan quando o canal sensor/PWM necessário não estiver disponível.

### 2026-07-20

- **Adicionado:** `start.sh` agora se auto-atualiza a cada execução. Quando executado a partir de um clone git, ele faz `fetch` de `origin/main` e faz `hard-reset` para o commit mais recente, re-executando se houver mudanças. Quando executado standalone, ele faz o bootstrap do repositório completo em `~/.bc250-toolkit/bc250-steamos-real-toolkit`, como antes.
- **Removido:** A opção de menu manual `Update Script` (`U`) e a função `run_update_script()` não são mais necessárias, pois as atualizações acontecem automaticamente na inicialização.

### 2026-07-19

- **Adicionado:** `start.sh` agora faz auto-bootstrap quando baixado standalone (ex.: instalação via `curl` one-liner). Se os assets vendored em `external/` estiverem faltando, ele baixa o repositório completo do toolkit em `${REAL_HOME}/.bc250-toolkit/bc250-steamos-real-toolkit` via `git` (com fallback de `curl`+`tar`) e re-executa a partir de lá.
- **Corrigido:** `cpu_governor_setup()` agora recria o `bc250-smu-oc.service` a partir de um `/etc/bc250-smu-oc.conf` existente quando o repositório vendored `bc250_smu_oc` não estiver presente, evitando a falha `Unit bc250-smu-oc.service does not exist`.

### 2026-07-18

- **Alterado:** Driver WiFi/BT AIC8800D80 USB movido de "Install All" / "Install Manual" para o menu `Extras` e agora usa `A` (instalar) e `R` (reverter). O driver não usa mais o `steamdeck-setup.sh` da vendor; ele compila e instala os módulos AIC8800, firmware, regra udev e dados usb_modeswitch diretamente, somente WiFi.
- **Alterado:** Repositórios de correções da comunidade (`bc250_smu_oc`, `nct6687d`) e o repositório principal de correções agora são clonados/vendored em `$SCRIPT_DIR/external/` em vez de `~/.local/share/`, mantendo os scripts ativos locais e em cache. O `.gitignore` agora exclui artefatos gerados de build de kernel dentro de `external/`.
- **Alterado:** Letras do menu `Extras` reorganizadas alfabeticamente (`A`, `F`, `H`, `K`, `P`, `R`, `X`, `0`).
- **Adicionado:** Persistência de atualização do SteamOS. O toolkit registra os componentes instalados em `${REAL_HOME}/.bc250-toolkit/installed-components`; habilitar a persistência em `Extras` (`P`) instala o `bc250-toolkit-persist.service` e uma keep list do `atomic-update`. Após uma atualização do SteamOS, o toolkit reinstala os componentes perdidos e restaura as configs salvas.
- **Adicionado:** Snapshots de config para overclock de CPU/GPU (`/etc/bc250-smu-oc.conf`, `/etc/cyan-skillfish-governor-smu/config.toml`) e CoolerControl (`/etc/coolercontrol`), restaurados automaticamente após o re-apply.
- **Melhorado:** Visibilidade dos comandos em execução com mensagens curtas `[context] starting...` / `[context] completed.` em `run_with_retry()` e `steamos_writable()` sem poluir a saída.
- **Melhorado:** Logs de erro de diagnóstico agora incluem um trace completo `set -x` e as últimas linhas da saída capturada.
- **Melhorado:** Falhas de rede/download agora perguntam `[R]etry` ou `[A]bort`; as perguntas são puladas no modo de re-apply desatendido (`AUTO=1`).
- **Melhorado:** `Install All` registra as etapas concluídas e oferece retomar a partir da última etapa inacabada na próxima execução.
- **Corrigido:** Instalação da persistência não inicia mais o `bc250-toolkit-persist.service` imediatamente (`enable` somente), evitando um travamento recursivo do re-apply.
- **Corrigido:** Instalação do WiFi/BT AIC8800 falhava com `Update persistence helper missing: /home/deck/tools/bc250/bc250-update-persistence.sh`. O toolkit agora cria o link do helper a partir do repositório de correções no local esperado antes de executar `steamdeck-setup.sh`.

- **Alterado:** Opções de instalar e reverter o driver AIC8800 no menu `Extras` foram agrupadas em um submenu dedicado.
- **Alterado:** Opções de habilitar e visualizar a persistência do SteamOS no menu principal foram agrupadas em um submenu (`E` / `V`).
- **Corrigido:** Lista de persistência agora detecta e registra automaticamente os componentes do toolkit já instalados, para não perder nada ao habilitar a persistência depois.

### 2026-07-17

- **Corrigido:** Menu de status do ZSWAP mostrava "ZRAM off / ZSWAP on" mesmo quando `/sys/module/zswap/parameters/enabled` estava `N` após reiniciar. O toolkit agora habilita o ZSWAP em runtime imediatamente e só reporta ON quando o parâmetro runtime é `Y`.
- **Alterado:** Tamanho padrão do swapfile aumentado para 32G e swappiness padrão para 120 tanto no "Configure Swap" manual quanto no fluxo "Install All".
- **Alterado:** Opção 1 do menu principal agora descreve "Instalar todas as otimizações necessárias".
- **Melhorado:** Selecionar `0` para sair agora espera Enter antes de fechar, mantendo a janela do Konsole visível.

### 2026-07-15

- **Corrigido:** Correção de áudio/vídeo do DisplayPort falhava quando o release do kernel SteamOS continha apenas um SHA curto. O toolkit agora resolve o commit completo via `git ls-remote` e passa como `FULLSHA` para o script de patch do driver da comunidade, evitando o erro HTTP 422 da API do GitHub.
- **Corrigido:** Correção de áudio/vídeo do DisplayPort parava durante a extração de dependências porque o pipeline upstream `tar | sed | awk` saía cedo sob `pipefail`. O toolkit agora aplica um patch de compatibilidade antes de executar o build.
- **Adicionado:** Um aviso de atualização do SteamOS é mostrado a cada inicialização e documentado em ambos os READMEs. Os usuários são instruídos a verificar o status do toolkit após cada atualização e a estar preparados para reinstalar componentes, especialmente no canal Beta.
- **Melhorado:** Sessões iniciadas da área de trabalho agora usam `konsole --hold`, erros não tratados geram logs de diagnóstico, e os logs são copiados para a Área de Trabalho quando disponível.
- **Melhorado:** `sudo` é autenticado uma vez na inicialização e seu timestamp é renovado durante a sessão, então instaladores aninhados não devem pedir a senha repetidamente.

### 2026-07-14

- **Renomeado** o script principal de `bc250-tollkit-steam-os-real.sh` (erro de digitação) para `start.sh`. `TOOLKIT_RAW_URL` (auto-atualizador) e comandos de instalação em ambos os READMEs foram atualizados.
- **Corrigido:** `[ERR] failed to read cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK with umr` reportado por usuários. `select_asic()` agora tenta detectar automaticamente o seletor ASIC correto via `umr -lb` antes de desistir, cobrindo placas onde o seletor padrão `cyan_skillfish.gfx1013` não corresponde.
- **Corrigido:** `bc250-detect: command not found` quando o usuário já tinha o governor de CPU instalado e escolheu não reinstalar (respondeu `n`). O script ia direto para `cpu_governor_setup()` sem adicionar o diretório pipx ao `PATH`. Corrigido prepondo `/root/.local/bin` e `/home/deck/.local/bin` no topo de `cpu_governor_setup()`.

### 2026-07-12

- **Corrigido:** Menu 2 → opção 9 (CU Unlock Live) estava fechando o toolkit inteiro quando o usuário pressionava `q` para sair do gerenciador de CU. Causa raiz: `bc250-cu-live-manager.sh` chama `exit 0` ao sair, que se propagava para o script pai. Corrigido executando o sub-script em subshell: `( bash "$CU_LIVE_MANAGER" )`.

### 2026-07-11 (2)

- **`game-save-sync`** foi extraído para seu próprio repositório standalone: [nonsteam-save-sync](https://github.com/rpf16rj/nonsteam-save-sync). Não faz mais parte deste toolkit. Veja aquele repositório para instruções de instalação e uso.

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

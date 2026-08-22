# Changelog

Todas as mudanças relevantes do BC-250 SteamOS Real Toolkit são documentadas
aqui. As versões seguem [Versionamento Semântico](https://semver.org/lang/pt-BR/)
(`MAJOR.MINOR.PATCH`) a partir da `v1.0.0`. Mudanças anteriores ficam abaixo
como histórico datado de antes da adoção de versões numeradas.

🇺🇸 Prefer English? Read the [CHANGELOG.md](./CHANGELOG.md).

## v1.6.0 — 2026-08-22

- **Novo:** Instalador de firmware Intel BE200 Wi-Fi 7 adicionado ao
  menu Extras — baixa e instala o firmware do BE200 para a placa ser
  reconhecida sem precisar recompilar o kernel.
- **Novo:** Patch ALLM-via-DP adicionado ao build do audio-fix — envia
  AVI infoframe com `content_type=Game` via DP SDP para PCONs DP-to-HDMI
  (ex. CH7218) em Source Control Mode, permitindo o PCON gerar
  autonomamente o HDMI Forum VSIF com ALLM. Também habilita Source
  Control Mode e HDMI Link via DPCD. Nota: a ativação do ALLM depende do
  firmware do PCON; o CH7218 com firmware Dp6.0.30 aparentemente ainda
  não gera HF-VSIF autonomamente.
- **Fix:** build do amdgpu agora tenta novamente com `-j1` se o GCC 15.x
  der erro interno (ICE) durante o build paralelo.

## v1.5.0 — 2026-08-21

- **Novo:** Fix do PS Button do DS5 Bridge — `hid-playstation.ko` patchado
  para expor `BTN_MODE` no DS5-Linux-Bridge, habilitando chord combos do
  Steam/Gamescope (PS+Cruz=QAM, PS+Triângulo=Steam overlay) com config
  customizada de chord VDF no Steam.
- **Novo:** Patches de Mesa/RADV atualizados com a versão mais recente
  do MastaG (Ago 2026) — compute queue fix, mesh/task shaders,
  taskmesh queries e promoção opt-in `RADV_GFX103=1` para GFX10.3
  todos atualizados.
- **Novo:** FSR4 V3 deferred SDot hybrid (de dmorazasanchez/bc250-fsr4)
  substitui o V2 selective sdot — adiciona fusão `iadd(0,SDot)`, cadeias
  MAD24 e pré-pass denso de SDot para melhor throughput INT8.
- **Novo:** Opção de native mesh shaders (de lonewolf0622) — shaders
  MESH-only no GFX10 sem spoofing de GFX10.3. Selecionável na instalação
  junto com a abordagem mesh/task do MastaG.
- **Novo:** Patch de EDID VRR para FreeSync via PCON DP→HDMI — zera o
  VTEM HDMI para evitar flickering, adiciona AMD VSDB v1 para FreeSync.
- **Corrigido:** Detecção de EDID no sysfs — `[[ -s ]]` reporta tamanho
  0 em arquivos sysfs; trocado por `wc -c` para o patch VRR funcionar.

## v1.4.0 — 2026-08-19

- **Novo:** Faixa SMU SCLK ampliada para 350–2230 MHz (patch do MastaG),
  permitindo governors de userspace usarem a faixa completa de clock.
- **Novo:** Otimização FSR4 dp4a agora usa abordagem seletiva — evita
  register spilling catastrófico em shaders patológicos mantendo o ganho
  de performance na maioria dos kernels.
- **Novo:** Guia de implementação de encoding AC-3 via HDMI para outros
  sistemas operacionais (documenta o plugin ALSA a52 + PipeWire).
- **Corrigido:** Instalação do adaptador Xbox (xone-dkms) agora detecta
  e instala o pacote correto de kernel headers antes de compilar o
  módulo DKMS.
- **Removido:** Flags de clock gating (`--cg`/`--cg-unvalidated`) e
  patches removidos do fix combinado — o recurso era experimental e não
  validado no hardware BC-250.

## v1.3.1 — 2026-08-17

- **Corrigido:** Instalação/reversão do AC-3 Surround agora funciona
  corretamente quando o toolkit é executado via `sudo`. Comandos do
  PipeWire e WirePlumber são executados em um script separado de sessão
  de usuário (`ac3-user-setup.sh`) como o usuário real, corrigindo
  falhas e travamentos na detecção da placa de áudio que ocorriam quando
  `pactl`/`systemctl --user` eram chamados como root.
- **Corrigido:** Configuração do WirePlumber corrigida para usar
  `api.acp.disable-pro-audio` em vez de `api.alsa.use-acp`, correspondendo
  ao perfil de hardware valve-fremont da Valve. A configuração anterior
  impedia o carregamento do conjunto de perfis `hdmi-ac3.conf`, deixando
  apenas perfis genéricos `on`/`off`.
- **Novo:** Status do AC-3 Surround agora exibido em "Verificar Minha
  Instalação" (opção V) com uma seção de Áudio dedicada mostrando se o
  AC-3 está instalado e se o perfil está atualmente ativo.
- **Alterado:** Logs do toolkit (trace, execução, erro, diagnóstico) agora
  salvos em `<diretório-toolkit>/logs/` em vez de `~/.bc250-toolkit/logs/`.
  Logs de erro ainda são copiados para a Área de Trabalho em caso de falha.

## v1.3.0 — 2026-08-17

- **Novo:** Codificação AC-3 Surround via HDMI — ativa codificação Dolby
  Digital 5.1 em tempo real por HDMI/DisplayPort via eARC. Antes era
  impossível no SteamOS com o BC-250 porque o perfil de hardware que
  carrega os perfis de áudio AC-3 nunca era ativado (o DMI do BC-250
  identifica como "AMD BC-250" em vez de "OEM F7F" da Valve). Isso
  instala uma regra udev e uma configuração do WirePlumber que ativa o
  conjunto de perfis `hdmi-ac3.conf` nativo, criando um sink 5.1 que
  codifica todo o áudio para AC-3 via o plugin `a52` do ALSA. Funciona
  com qualquer adaptador DisplayPort-para-HDMI ativo (não é específico
  de marca). Latência zero adicionada, ~1-2% de overhead de CPU. Conteúdo
  stereo é automaticamente upmixado para 5.1. O sink permanece ativo por
  1 hora após o último som para evitar que o receiver volte para PCM.
  Após instalar, selecione "HD-Audio Generic Digital Surround 5.1
  (HDMI/AC3)" nas configurações de dispositivo de áudio do KDE (Modo
  Desktop) para ativar a saída Dolby Digital. Disponível como opção
  13/13R no menu.

## v1.2.2 — 2026-08-16

- **Corrigido:** Falha na compilação do Mesa em alguns sistemas SteamOS —
  dependências de build ausentes (`zstd`, `glslang`, `python-yaml`) agora
  são instaladas automaticamente, e a flag `--needed` foi removida para
  que o pacman reinstale pacotes cujos arquivos `.pc` e headers foram
  removidos da imagem do SteamOS.
- **Corrigido:** Verificação pós-instalação agora confirma que os
  arquivos pkgconfig críticos estão presentes antes de tentar o build.

## v1.2.1 — 2026-08-16

- **Corrigido:** Stuttering de áudio sob alto load — amostragem GRBM reduzida
  de 32 para 16 iterações e cache aumentado de 25ms para 100ms, reduzindo
  overhead de CPU em 8x (de ~6.2% para ~0.78%).
- **Corrigido:** Falha na aplicação de patches no SteamOS 3.8.16 — adicionado
  `--fuzz=3` a todos os comandos de patch para maior tolerância a offsets de
  linha.
- **Corrigido:** Falha na instalação de pacotes AUR em locales em português —
  erros de verificação de validade agora são detectados como erros de rede
  recuperáveis, com limpeza automática do cache antes de tentar novamente.
- **Corrigido:** URL do repositório do MastaG corrigida nos créditos.

## v1.2.0 — 2026-08-15

- **Novo:** Opção de instalação combinada Audio + GFX1013 — compila ambos os
  fixes num único módulo de kernel, economizando tempo e evitando reboots
  duplicados.
- **Novo:** Telemetria de GPU atualizada com cache de 100ms e amostragem GRBM
  de 16 iterações para relatórios de frequência e atividade responsivos sem
  stuttering de áudio sob alto load. Inclui modo de telemetria completa
  (opt-in via `pp_dpm_socclk`) e suporte a métricas híbridas de 8 núcleos.
  Baseado no [patch de telemetria do MastaG](https://github.com/MastaG/linux-cachyos-bc250).
- **Novo:** Guarda defensiva TTM NULL-page — previne kernel panic na
  limpeza parcial de alocação de memória da GPU. Sempre aplicado, sem
  configuração necessária.
  Baseado no [patch TTM do MastaG](https://github.com/MastaG/linux-cachyos-bc250).
- **Novo:** Workaround opcional de flush de runlist KFD para usuários de
  ROCm/compute (opt-in via `amdgpu.bc250_flush_by_runlist=1`).
  Baseado no [patch KFD do MastaG](https://github.com/MastaG/linux-cachyos-bc250).
- **Melhoria:** +20-25% de performance de GPU em workloads de compute assíncrono
  (ex.: Cyberpunk 2077) graças à correção de fila de compute GFX1013.
- **Melhoria:** Performance de shaders FSR 4 — a otimização de dot-product INT8
  (`imul24_relaxed`) está incluída no Mesa 26.2.0-rc3, resultando em ~42%
  menos instruções e ~61% menos latência nos shaders do FSR 4. Basta ativar
  o FSR 4 nos jogos — o driver já está otimizado.
  Baseado em [dmorazasanchez/bc250-fsr4](https://github.com/dmorazasanchez/bc250-fsr4).
- **Corrigido:** Compatibilidade do build do Mesa com todas as versões do
  glibc — a verificação de ETIME agora detecta se `_GNU_SOURCE` é necessário
  e patcheia o Mesa adequadamente, prevenindo falhas de build em glibc
  antigo e novo.
- **Corrigido:** Falha na aplicação de patches ao atualizar de uma versão
  anterior — o arquivo de header do kernel agora é corretamente resetado
  antes de aplicar novos patches.

### Agradecimentos

Este release integra patches da comunidade BC-250:
- **MastaG** ([@MastaG](https://github.com/MastaG)) — patches de telemetria
  de GPU, guarda TTM NULL-page e flush de runlist KFD.
- **dmorazasanchez** ([@dmorazasanchez](https://github.com/dmorazasanchez)) —
  pesquisa e otimização de dot-product INT8 para FSR 4 no BC-250.
- **keyboardspecialist** ([@keyboardspecialist](https://github.com/keyboardspecialist)) —
  fixes originais do BC-250 SteamOS (ACPI, áudio DP, WiFi).

## v1.1.5 — 2026-08-14

- **Corrigido:** o build do Mesa ainda falhava com `Could not get define 'ETIME'`
  no glibc 2.43 mesmo após o fix da v1.1.4. A causa raiz: `cc.has_define()`
  chama `cc.get_define()` internamente, então lança o mesmo erro. O script de
  build agora patcheia o prefix do `get_define` no `meson.build` para incluir
  `#define _GNU_SOURCE` — o glibc 2.43 esconde o `ETIME` atrás do `_GNU_SOURCE`,
  e o `get_define` do Meson usa apenas o prefix (não os `pre_args` do projeto).
  Assim o `get_define` encontra `ETIME=62` diretamente, evitando tanto o erro
  quanto qualquer conflito de redefinição.

## v1.1.4 — 2026-08-13

- **Corrigido:** o build do Mesa ainda falhava com `Could not get define 'ETIME'`
  em sistemas com GCC 15.x + glibc 2.43 (ex.: SteamOS 3.8.16). A causa raiz é
  que o `cc.get_define()` do Meson 1.8.2 erroa em vez de retornar string vazia
  quando o define está faltando, quebrando o próprio fallback do Mesa. O script
  de build agora patcheia o `meson.build` do Mesa para usar `cc.has_define()`
  (que retorna booleano), fazendo o fallback funcionar corretamente.

## v1.1.3 — 2026-08-12

- **Corrigido:** o build do Mesa ainda falhava com `Could not get define 'ETIME'`
  mesmo com o fix da v1.1.2, porque `-Dc_args` não afeta as verificações de
  compilador do Meson. O define de fallback agora é exportado via `CFLAGS`,
  que o `cc.get_define()` do Meson de fato respeita.

## v1.1.2 — 2026-08-11

- **Corrigido:** a etapa de build do Mesa da correção GFX1013 podia falhar
  durante o `meson setup` com `Could not get define 'ETIME'` em algumas
  combinações de glibc/GCC (notavelmente GCC 15.x). O script de build agora
  detecta o define faltante e injeta um fallback (`-DETIME=ETIMEDOUT`) para
  que a configuração complete com sucesso.

## v1.1.1 — 2026-08-11

- **Corrigido:** a correção GFX1013 (e a correção de áudio comum, que usa a
  mesma etapa de build) podia falhar ao instalar em alguns sistemas por um
  erro de compilador em uma ferramenta de build do kernel sem relação com a
  correção, desbloqueando a etapa afetada do build.

## v1.1.0 — 2026-08-09

- **Novo:** Correção de Compute GFX1013 (opção 11 do menu) — melhora o
  desempenho de computação da GPU e corrige jogos que não abriam ou
  rodavam de forma incorreta na GPU do BC-250.
- Adicionada uma linha de status para a nova correção no menu principal.
- A correção pode ser instalada e revertida a qualquer momento pelo menu.

## v1.0.5 — 2026-08-03

- **Corrigido:** o revert completo do `build.sh` pro estado de 2026-08-01 na
  v1.0.4 removeu o passo de reset da árvore pro estado pristine antes da
  stack de patches, exatamente como avisado na hora. Isso trouxe de volta o
  bug de "árvore desviou" que aquele passo corrigia: o `fetch-sources.sh`
  reaproveita a árvore de kernel vendorizada entre execuções assim que ela
  já está no commit certo, então um arquivo deixado num estado de uma
  tentativa de patch anterior podia falhar em aplicar OU reverter de forma
  limpa contra o texto do patch atual, abortando a build inteira. Ocorreu na
  prática: `apply Cyan Skillfish GPU telemetry patch` falhou com exatamente
  esse erro numa build real depois do revert da v1.0.4. Resetei manualmente
  a árvore afetada (`cyan_skillfish_ppt.c`) pro estado pristine pra
  destravar a instalação em andamento, e reintroduzi o passo de reset no
  `build.sh` — restrito só aos arquivos que a stack atual de dois patches
  toca (`cyan_skillfish_ppt.c`, `dcn201_clk_mgr.c`, `clk_mgr.c`), sem
  aplicar o patch de 8 núcleos junto.

## v1.0.4 — 2026-08-03

- **Revertido:** `external/bc250-steamos/bc250-audio-fix/` (sistema de build
  e conjunto de patches do fix de áudio/vídeo DisplayPort + métricas de GPU)
  foi revertido de volta ao estado exato de 2026-08-01 (commit `1e3b9f0`, o
  dia em que a opção de menu `bc250-detect` foi adicionada), em cima do
  `gfxclk.patch` já revertido na v1.0.2. O
  `bc250-cyan-skillfish-8core-metrics.patch` — adicionado em 2026-08-02,
  totalmente novo naquele dia — foi removido; o `build.sh` não aplica mais
  esse patch nem reseta a árvore vendorizada pra um checkout pristine antes
  da stack de patches (também adicionado em 2026-08-02). O `README.md` foi
  revertido pra bater. Efeito líquido: só restam o patch de clock de
  áudio/vídeo DP, a telemetria de atividade via GC, e o `gfxclk` de consulta
  direta via SMU sem validação, batendo com o último estado conhecido antes
  do trabalho de métricas de 8 núcleos Robin 3.00 e suas
  regressões/correções subsequentes (v1.0.0 até v1.0.3). Verificado que a
  stack de dois patches resultante aplica limpa contra um checkout pristine
  recém-criado.

## v1.0.3 — 2026-08-02

- **Corrigido:** o auxiliar `audio_fix_resolve_fullsha()` de
  `install_audio_fix()` rodava `git ls-remote
  https://github.com/Evlav/linux-integration.git` sem timeout pra resolver
  antecipadamente o SHA completo (40 caracteres) do commit do kernel em
  execução. Em pelo menos uma ocasião essa chamada enviou a requisição HTTP/2
  `git-upload-pack` e nunca recebeu resposta (reproduzido e confirmado: um
  GET HTTPS simples na mesma URL respondeu na hora, mas o `git ls-remote` em
  si travou por mais de 30s), congelando todo o fluxo de retomada do
  "Install All" logo após "Running patch-driver.sh...". O chamador já tolera
  falha na resolução (`|| true`, caindo pro `fetch-sources.sh` resolver o
  commit sozinho via API REST do GitHub), mas esse fallback nunca chegava a
  rodar porque a chamada bloqueante em si nunca retornava. Envolvida em
  `timeout 15`.

## v1.0.2 — 2026-08-02

- **Revertido:** o wrapper de validação de faixa do
  `bc250-cyan-skillfish-gfxclk.patch` (adicionado na v1.0.0, parcialmente
  corrigido na v1.0.1) foi totalmente revertido de volta pra consulta direta
  e incondicional via SMU `GetGfxclkFrequency` — a versão confirmada
  funcional antes da v1.0.0. O teste de campo da v1.0.1 mostrou o % de
  atividade da GPU voltando a funcionar (esperado — aquele fix removeu o
  abort da struct inteira), mas o clock em MHz continuou travado em 0 e a
  temperatura da GPU continuou congelada: o valor de fallback usado numa
  leitura de clock rejeitada/inválida, `metrics.Current.GfxclkFrequency` da
  tabela `SmuMetrics_t` do firmware, é ele mesmo sempre zero/obsoleto nesse
  hardware — essa instabilidade é exatamente o motivo pelo qual a consulta
  direta via SMU foi criada em primeiro lugar, então usá-la como fallback
  não resolvia nada. A causa raiz do congelamento de temperatura junto com o
  MHz travado em 0 precisa de mais investigação de campo a partir dessa
  base revertida antes de qualquer nova tentativa de validação de faixa do
  gfxclk.

## v1.0.1 — 2026-08-02

- **Corrigido:** o `bc250-cyan-skillfish-gfxclk.patch` (introduzido na v1.0.0)
  fazia `cyan_skillfish_get_gpu_metrics()` retornar cedo demais — descartando
  a leitura *inteira* de `gpu_metrics` (temperatura da GPU, % de atividade da
  GPU, e todas as métricas por-núcleo de CPU, não só o clock) — sempre que
  sua própria consulta direta de clock GFX via SMU com validação de faixa
  vinha fora de `CYAN_SKILLFISH_SCLK_MIN`/`MAX` ou falhava por outro motivo.
  Na prática isso deixava o relato de carga/temperatura da GPU parado ou
  mostrando 0% em idle, só "recuperando" quando a carga empurrava o clock de
  volta pra faixa válida — o que por sua vez impedia a curva de fan
  gerenciada de subir a tempo e podia deixar a placa superaquecer sob carga
  sustentada. Agora a falha na consulta de clock só cai de volta pro valor
  bruto (sem validação) `metrics.Current.GfxclkFrequency` para esse campo
  específico; todos os outros sensores de `gpu_metrics` continuam
  atualizando normalmente a cada leitura.

## v1.0.0 — 2026-08-02

Primeira versão numerada. Adota versionamento semântico e GitHub Releases
(zip para download) em vez de versões com data e do instalador `curl | bash`.

- **Alterado:** Distribuição migrou de um one-liner `curl`-piped do
  `start.sh` / clone git com auto-update para GitHub Releases versionados.
  Baixe o zip da release mais recente, extraia e rode o `start.sh` — veja a
  seção Instalação Rápida no README.
- **Removido:** Auto-update a cada abertura (`git fetch origin main` +
  `reset --hard` no início do `start.sh`). Ele descartava silenciosamente
  qualquer alteração local não commitada ao abrir, podendo apagar trabalho
  em andamento. Atualizar o toolkit agora significa baixar o zip da release
  mais recente. O bootstrap standalone (buscar o repositório completo quando
  `start.sh` roda sem os assets vendorizados de `external/`) não foi afetado.
- **Adicionado:** `bc250-cyan-skillfish-8core-metrics.patch` em
  `external/bc250-steamos/bc250-audio-fix`, vendorizado da versão mais nova
  de [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos).
  Em BIOS Robin 3.00 + topologia 8-core/16-thread totalmente desbloqueada
  (`CPU Core Unlock`), lê power/temperatura/frequência reais por-núcleo dos
  8 núcleos direto da tabela `PMSTATUSLOG` da SMU via acesso direto a
  registrador PCIe, em vez do layout `SmuMetrics_t` de fábrica, que só
  carrega 6 entradas de núcleo — o patch set anterior duplicava/truncava
  silenciosamente os dados por-núcleo em sistemas 8-core desbloqueados. Cai
  de volta pro relato de 6 núcleos do `SmuMetrics_t` (`-ENODEV`) em qualquer
  outra topologia, então é seguro em sistemas 6c/12t sem modificação também.
  Nota: o arquivo de patch publicado originalmente estava truncado (faltavam
  chaves de fechamento) — completado manualmente e verificado para aplicar
  de forma limpa e gerar C sintaticamente válido contra a árvore de kernel
  vendorizada deste toolkit antes de ser incorporado.
- **Alterado:** `bc250-cyan-skillfish-gfxclk.patch` atualizado para a versão
  mais nova upstream, que envolve a consulta direta de clock GFX via SMU em
  validação de faixa (descarta leituras fora de
  `CYAN_SKILLFISH_SCLK_MIN`/`MAX` em vez de propagar valores inválidos para
  `gpu_metrics`/hwmon).
- **Corrigido:** o `build.sh` reaproveitava uma árvore de kernel já com
  patch aplicado entre execuções separadas (`fetch-sources.sh` pula o
  re-checkout quando a árvore já está no commit do kernel em execução, por
  design, para ganhar velocidade). Quando o *conteúdo* de um patch
  vendorizado muda entre execuções — como a atualização do `gfxclk.patch`
  acima — o arquivo deixado por um build anterior podia ficar num estado que
  não aplicava nem revertia de forma limpa contra o novo texto do patch,
  abortando com "tree has drifted". O `build.sh` agora reseta exatamente os
  arquivos que sua cadeia de patches toca (`cyan_skillfish_ppt.c`,
  `dcn201_clk_mgr.c`, `clk_mgr.c`) para o estado pristine do git antes de
  aplicar os patches, em toda execução.

## Histórico pré-1.0 (versões datadas)

### 2026-08-01

- **Adicionado:** `RAM/VRAM Split` em `Install Manual` (`10`/`10R`) e `Install All`/`Revert All`. Traz vendorizado o [fanoush/bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (compilado localmente na instalação) para reduzir o `UMA_SIZE` do split permanente de fábrica (8192MB, 8GB/8GB) para o piso mínimo documentado de 512MB na CMOS com bateria da BC-250, liberando quase toda a RAM de 16GB em idle, e eleva o teto dinâmico de VRAM do kernel via `ttm.pages_limit` no GRUB (~12GB) para jogos que pedem 8GB+ de VRAM não travarem com o split mais baixo. Não precisa de BIOS modificada; o status mostra o `UMA_SIZE` atual. Corrigidos dois bugs encontrados em seguida: o build agora força a reinstalação de `glibc`/`base-devel` quando o `gcc` não consegue de fato compilar um programa C (os headers podem sumir/ser removidos do overlay do SteamOS mesmo com o `gcc` presente), e a comparação do readback pós-escrita na CMOS agora remove o zero-padding do `bc250memcfg` (`0512`) antes de comparar.
- **Adicionado:** Auto-reboot opcional para o `Desbloqueio de Núcleos de CPU`. Após um power-off frio, a AGESA só relê a máscara de núcleos reescrita no boot *seguinte* (não naquele em que o serviço de boot a reaplica), então recuperar os 2 núcleos extras sempre custa mais um reboot. A instalação agora pergunta se quer disparar esse segundo reboot obrigatório automaticamente, salvando a escolha em `/etc/bc250-core-unlock.conf`; o serviço de boot só reinicia sozinho logo após uma escrita nova da máscara com os núcleos ainda inativos, nunca num boot que já estava desbloqueado — evitando loop de reboot em caso de falha real de enumeração.
- **Adicionado:** `Run bc250-detect` (`D`) no menu de Perfil de Performance, para reajustar manualmente o undervolt da CPU com frequência/tensão/temperatura alvo personalizadas — útil após ligar/desligar o `Desbloqueio de Núcleos de CPU`, já que 6c/12t vs 8c/16t muda o perfil elétrico/térmico da CPU o suficiente para um `scale` ajustado antes deixar de ser o ideal.
- **Corrigido:** O status do `Desbloqueio de Núcleos de CPU` mostrava fixo "6c/12t, SteamOS default" sempre que o serviço de boot não estava instalado, mesmo que o revert só remova esse serviço — a própria máscara de núcleos (e portanto o estado real 8c/16t) permanece ativa até um power-off frio de verdade. O status agora checa a contagem real de núcleos também nesse caso.

### 2026-07-30

- **Adicionado:** `Desbloqueio de Núcleos de CPU` em `Install Manual` (`9`/`9R`) e em `Install All`/`Revert All`. Traz vendorizado o [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock), que escreve a máscara de presença de núcleos da BC-250 via mensagem na mailbox da SMU para habilitar os 2 núcleos de CPU desabilitados (6c/12t → 8c/16t). Nenhuma adaptação específica do SteamOS foi necessária — o script upstream só acessa o espaço de configuração PCI e o serviço já existente do governor de GPU. Como a escrita é volátil após um power-off frio, a instalação cria um serviço systemd de boot (`bc250-core-unlock.service`) que reaplica a escrita a cada inicialização; o status agora mostra a contagem atual de núcleos/threads. ⚠ Experimental — veja `external/bc250-core-unlock/README.md` para as ressalvas (possível binning de silício, bug de leitura de clock da GPU).
- **Alterado:** `Install ACPI Fix` agora busca as tabelas SSDT-CST/SSDT-PST de [mendesrr/bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c) em vez das da bc250-collective, já que a comunidade relatou que as tabelas originais (só 6c) se comportam mal depois que os 2 núcleos extras são desbloqueados. Instalações existentes atualizam automaticamente na próxima vez que a correção de ACPI rodar. `Desbloqueio de Núcleos de CPU` agora instala/atualiza essa correção de ACPI de forma transparente na mesma execução, sem confirmação extra, então as duas correções são sempre aplicadas juntas.
- **Alterado:** Re-vendorizado `external/bc250-steamos/bc250-audio-fix` do upstream [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos), que agora também corrige `cyan_skillfish_ppt.c` para consultar o clock GFX direto da SMU e adicionar o relato de utilização de GPU (`bc250-cyan-skillfish-gfxclk.patch`, `bc250-cyan-skillfish-gpu-telemetry.patch`) — a correção reportada pela comunidade para as métricas de clock/carga da GPU ficarem imprecisas depois que os 2 núcleos extras são desbloqueados. `Install DP Audio/Video Fix` (Install Manual `7`) aplica isso junto com a correção de clock do DisplayPort já existente; não é encadeado automaticamente no `Desbloqueio de Núcleos de CPU` já que recompila um módulo do kernel, mas o `Install All` já roda antes do passo de desbloqueio de núcleos. Também vendorizado o helper `fetch-steamos-package.sh` do upstream (descoberta de pacote SteamOS multi-canal) e corrigido uma falsa-falha no workaround de SIGPIPE deste toolkit agora que o upstream corrigiu esse bug de forma independente.
- **Adicionado:** `RAM/VRAM Split` em `Install Manual` (`10`/`10R`) e `Install All`/`Revert All`. Traz vendorizado o [fanoush/bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (compilado localmente a partir do código-fonte na instalação) para escrever `UMA_SIZE=512` na CMOS com bateria da BC-250 — a BIOS de fábrica reserva um valor fixo de 8192MB (split 8GB/8GB) permanentemente para VRAM, e 512MB é o piso mínimo documentado, liberando quase toda a RAM de 16GB em idle. Também eleva o teto dinâmico de VRAM do kernel via `ttm.pages_limit` no GRUB (~12GB), já que o teto padrão com um piso de 512MB pode ser baixo demais para jogos que pedem 8GB+ de VRAM. Não precisa de BIOS modificada; o status mostra o `UMA_SIZE` atual. O revert restaura o split de fábrica de 8192MB e remove o override do GRUB.
- **Corrigido:** o `nano` perdia a navegação por setas ao editar a config de CPU/GPU (menu Performance `F`/`E`) — o redirecionamento `exec > >(tee ...) 2>&1` do run-log do toolkit deixava o stdout do `nano` como um pipe em vez de um TTY de verdade, quebrando o endereçamento de teclado/cursor do ncurses. Os dois editores agora falam direto com `/dev/tty`.

### 2026-07-26

- **Corrigido:** O bootstrap standalone de um clique agora corrige a propriedade de `~/.bc250-toolkit` antes de clonar como o usuário desktop, evitando `could not create work tree dir: Permission denied` após execuções anteriores como root.
- **Corrigido:** As auto-atualizações via git agora rodam como o usuário desktop e corrigem a propriedade do checkout primeiro, evitando `dubious ownership`, `.git/FETCH_HEAD: Permission denied`, e prompts de salvamento da IDE causados por arquivos do repositório de propriedade do root.
- **Corrigido:** A ativação em tempo real do ZSWAP agora persiste após reiniciar através de uma regra do systemd-tmpfiles em kernels SteamOS que ignoram `zswap.enabled=1`; o status também distingue ZSWAP configurado-mas-inativo.

### 2026-07-23

- **Adicionado:** A opção `Z` de `Extras` instala o plugin Decky Toolkit SteamOS Control pré-compilado. Instala o Decky Loader estável automaticamente quando necessário, copia o artefato do plugin já pronto, e reinicia o loader sem precisar de Node.js, pnpm, ou build local.
- **Adicionado:** Controles de Pump Fan automático, manual e gerenciado com curva de quatro pontos para o sensor/canal PWM NCT da BC-250, além de controles opcionais de efeitos da LED bar quando `steamos-led.service` está presente.
- **Adicionado:** Persistência SteamOS para a configuração de fan do Toolkit SteamOS Control e o serviço de fan gerenciado.
- **Melhorado:** A interface do Decky separa as visões de Cooler e LED bar, preserva mudanças não salvas dos sliders durante o polling de status, e desabilita os controles de Pump Fan quando o sensor/canal PWM necessário não está disponível.

### 2026-07-20

- **Adicionado:** o `start.sh` agora se auto-atualiza a cada abertura. Quando rodado de um clone git, ele busca `origin/main` e reseta forçadamente para o commit mais recente, reexecutando se algo mudou. Quando rodado como script standalone, ele faz bootstrap do repositório completo em `~/.bc250-toolkit/bc250-steamos-real-toolkit` como antes.
- **Removido:** a opção manual `Update Script` (`U`) do menu e a função `run_update_script()` não são mais necessárias porque as atualizações acontecem automaticamente na abertura.

  *(Ambos foram revertidos na v1.0.0 acima — o auto-update na abertura acabou sendo destrutivo para mudanças locais em andamento.)*

### 2026-07-19

- **Adicionado:** o `start.sh` agora faz bootstrap automático quando baixado sozinho (ex.: o instalador de uma linha via `curl`). Se os assets vendorizados de `external/` estão faltando, ele busca o repositório completo do toolkit em `${REAL_HOME}/.bc250-toolkit/bc250-steamos-real-toolkit` via `git` (com fallback via `curl`+`tar`) e reexecuta a partir dali.
- **Corrigido:** `cpu_governor_setup()` agora recria o `bc250-smu-oc.service` a partir de um `/etc/bc250-smu-oc.conf` existente quando o repositório vendorizado `bc250_smu_oc` não está presente, evitando a falha `Unit bc250-smu-oc.service does not exist`.

### 2026-07-18

- **Alterado:** o driver WiFi/BT USB AIC8800D80 saiu de "Install All" / "Install Manual" e foi para o menu `Extras`, usando agora `A` (instalar) e `R` (reverter). O driver não usa mais o `steamdeck-setup.sh` do fornecedor; ele compila e instala os módulos AIC8800, firmware, regra udev e dados do usb_modeswitch diretamente, WiFi apenas.
- **Alterado:** os repositórios de correções da comunidade (`bc250_smu_oc`, `nct6687d`) e o repositório principal de correções agora são vendorizados/clonados em `$SCRIPT_DIR/external/` em vez de `~/.local/share/`, mantendo os assets locais e em cache. O `.gitignore` agora exclui artefatos de build de kernel gerados dentro de `external/`.
- **Alterado:** as letras de opção do menu `Extras` foram reordenadas em ordem alfabética (`A`, `F`, `H`, `K`, `P`, `R`, `X`, `0`).
- **Adicionado:** persistência de atualização do SteamOS. O toolkit rastreia componentes instalados em `${REAL_HOME}/.bc250-toolkit/installed-components`; habilitar a persistência em `Extras` (`P`) instala o `bc250-toolkit-persist.service` e uma lista de "keep" do atomic-update. Após uma atualização do SteamOS, o toolkit reinstala componentes perdidos e restaura configs salvas.
- **Adicionado:** snapshots de configuração para overclock de CPU/GPU (`/etc/bc250-smu-oc.conf`, `/etc/cyan-skillfish-governor-smu/config.toml`) e CoolerControl (`/etc/coolercontrol`) que são restaurados automaticamente após reaplicar.
- **Melhorado:** visibilidade de comandos em execução com mensagens concisas de progresso `[contexto] iniciando...` / `[contexto] concluído.` em `run_with_retry()` e `steamos_writable()` sem poluir a saída.
- **Melhorado:** os logs de diagnóstico de erro agora incluem um trace completo de `set -x` e a saída capturada recente.
- **Melhorado:** falhas de rede/download agora perguntam `[R]etentar` ou `[A]bortar`; os prompts são pulados no modo de reaplicação não assistida (`AUTO=1`).
- **Melhorado:** o `Install All` rastreia as etapas concluídas e oferece retomar a partir da última etapa não finalizada na próxima execução.
- **Corrigido:** a instalação de persistência não inicia mais o `bc250-toolkit-persist.service` imediatamente (apenas `enable`), evitando um travamento por reaplicação recursiva.
- **Corrigido:** a instalação do WiFi/BT AIC8800 falhava com `Update persistence helper missing: /home/deck/tools/bc250/bc250-update-persistence.sh`. O toolkit agora cria um link do helper a partir do repositório de correções para o local esperado antes de rodar o `steamdeck-setup.sh`.
- **Alterado:** as opções de instalar e reverter o driver WiFi/BT AIC8800 em `Extras` agora estão agrupadas em um submenu dedicado.
- **Alterado:** as opções de habilitar e ver a Persistência de Atualização do SteamOS no menu principal agora estão agrupadas em um submenu (`E` / `V`).
- **Corrigido:** a lista de persistência agora detecta e registra automaticamente componentes já instalados do toolkit, então nada se perde ao habilitar a persistência depois do fato.

### 2026-07-17

- **Corrigido:** o menu de status do ZSWAP mostrava "ZRAM desligado / ZSWAP ligado" mesmo quando `/sys/module/zswap/parameters/enabled` era `N` após reiniciar. O toolkit agora habilita o ZSWAP em tempo real imediatamente e só reporta LIGADO quando o parâmetro em tempo real é `Y`.
- **Alterado:** o tamanho padrão do swapfile foi elevado para 32G e o swappiness padrão para 120, tanto na "Configuração de Swap" manual quanto no fluxo do "Install All".
- **Alterado:** a opção 1 do menu principal agora lê "Instalar todas as otimizações necessárias" em sua descrição.
- **Melhorado:** selecionar `0` para sair agora espera Enter antes de fechar, mantendo a janela do Konsole visível.

### 2026-07-15

- **Corrigido:** a Correção de Clock de Áudio/Vídeo DisplayPort falhava quando a release do kernel SteamOS continha apenas um SHA de commit curto. O toolkit agora resolve o commit completo via `git ls-remote` e o passa como `FULLSHA` para o script de patch do driver da comunidade, evitando o erro HTTP 422 da API do GitHub.
- **Corrigido:** a Correção de Clock de Áudio/Vídeo DisplayPort parava durante a extração de dependências porque o pipeline `tar | sed | awk` do upstream saía cedo demais sob `pipefail`. O toolkit agora corrige essa incompatibilidade antes de rodar o build.
- **Adicionado:** um aviso de atualização do SteamOS é mostrado a cada abertura e documentado em ambos os READMEs. Os usuários são instruídos a checar o status do toolkit após toda atualização e estar preparados para reinstalar componentes, especialmente com o canal Beta ativo.
- **Melhorado:** sessões abertas pela área de trabalho agora usam `konsole --hold`, erros não tratados geram logs de diagnóstico, e os logs de erro são copiados para a Área de Trabalho quando disponível.
- **Melhorado:** o `sudo` é autenticado uma vez no início e seu timestamp é renovado durante a sessão, então instaladores aninhados não devem pedir a senha repetidamente.

### 2026-07-14

- **Renomeado** o script principal de `bc250-tollkit-steam-os-real.sh` (erro de digitação) para `start.sh`. Atualizado o `TOOLKIT_RAW_URL` (auto-atualizador) e os comandos de instalação em ambos os READMEs de acordo.
- **Corrigido:** `[ERR] failed to read cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK with umr` reportado por usuários. `select_asic()` agora tenta auto-detectar o seletor ASIC correto via `umr -lb` antes de desistir, cobrindo placas onde o seletor padrão `cyan_skillfish.gfx1013` não bate.
- **Corrigido:** `bc250-detect: command not found` quando o usuário já tinha o governor de CPU instalado e escolhia não reinstalar (respondendo `n`). O script ia direto para `cpu_governor_setup()` sem adicionar o diretório bin do pipx ao `PATH`. Corrigido sempre adicionando `/root/.local/bin` e `/home/deck/.local/bin` no início de `cpu_governor_setup()`.

### 2026-07-12

- **Corrigido:** o menu 2 → opção 9 (CU Unlock Live) fechava o toolkit inteiro quando o usuário apertava `q` para sair do gerenciador de CU. Causa raiz: `bc250-cu-live-manager.sh` chama `exit 0` ao sair, o que se propagava para o script pai. Corrigido rodando o subscript em uma subshell: `( bash "$CU_LIVE_MANAGER" )`.

### 2026-07-11 (2)

- **O `game-save-sync`** foi extraído para seu próprio repositório standalone: [nonsteam-save-sync](https://github.com/rpf16rj/nonsteam-save-sync). Não faz mais parte deste toolkit. Veja aquele repositório para instruções de instalação e uso.

### 2026-07-11

- Adicionado um instalador de driver do Xbox Wireless Adapter em **Extras**: instala `dkms`, `xone-dkms`, e `xone-dongle-firmware` via o AUR helper, coloca na blacklist drivers conflitantes (`xpad`, `mt76x2u`), e carrega o `xone` automaticamente.
- Corrigido a atualização do repositório de Correções da Comunidade abortando quando um build anterior deixava artefatos locais (ex.: `amdgpu.ko.zst`) no checkout.

### 2026-07-09

- Simplificado e reorganizado todo o menu: **Install All**, **Install Manual**, **Perfis de Performance**, **Reverter/Desinstalar Tudo**, e **Extras** (sensores, CoolerControl, HDMI-CEC), além de acesso rápido a **Verificar Minha Configuração**, **Changelog**, **Atualizar Script**, e **Ajuda**.
- Adicionado um atualizador embutido, um atalho de área de trabalho criado automaticamente no primeiro uso, e as Mitigações de CPU + CU Unlock Live agora fazem parte do fluxo de instalação/desinstalação em um clique.
- Adicionado o ajuste de Swap/ZRAM→ZSWAP e o controle de HDMI-CEC / TV.
- Corrigido um bug que impedia a interface de controle remoto do governor de GPU de funcionar corretamente.

### 2026-07-08

- Adicionado monitoramento de sensores e fan para o chip onboard da BC-250, com controle total de PWM opcional.
- Adicionada a integração com CoolerControl para curvas de fan personalizadas.
- Adicionado o menu de Correções da Comunidade (estados de energia ACPI, correção de áudio/vídeo do DisplayPort, driver WiFi/BT AIC8800).
- Várias correções de confiabilidade de instalação validadas em hardware real.

### 2026-07-06

- Primeiro lançamento público: Install All / Uninstall All em um clique, CU Unlock Live, perfis de performance, log de erros automático, e reparo automático do keyring do pacman.

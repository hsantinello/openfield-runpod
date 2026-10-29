# OpenField no RunPod (template automático)

Template do RunPod que instala e liga o [OpenField](https://github.com/wexloops/openfield)
sozinho: ComfyUI, modelos, OpenField e uma tela de senha para você abrir pelo link do RunPod.
Sem terminal, sem Docker.

**Deploy:** https://console.runpod.io/deploy?template=wh0b9rwuwm

## Antes de começar (5 minutos)

1. Crie uma conta no [Hugging Face](https://huggingface.co).
2. Aceite a licença do LTX-2.5 em https://huggingface.co/Lightricks/LTX-2.5 (sem isso os modelos de vídeo não baixam).
3. Crie um token de leitura em https://huggingface.co/settings/tokens.

## Como usar

1. No RunPod, crie um **Network Volume** de **150 GB** (Storage → New Network Volume).
   Ele guarda os modelos, então você só baixa uma vez.
2. Abra o link de deploy acima, escolha o volume e uma GPU de **24 GB ou mais**
   (RTX 5090 é a ideal; L40S e RTX 4090 também servem).
3. Em **Edit Template / Environment Variables**, preencha:

   | Variável | O que colocar |
   |---|---|
   | `OPENFIELD_PASSWORD` | Sua senha para entrar (8+ caracteres) |
   | `HF_TOKEN` | O token do Hugging Face |
   | `OPENFIELD_BUNDLES` | Opcional. Padrão: `ltx25,qwen,edit,cutout,ltx-tools` (~92 GB) |

4. Clique em **Deploy**. No pod, vá em **Connect → HTTP Service porta 3170**.
   O navegador pede usuário e senha: o usuário pode ser qualquer coisa, a senha é a do `OPENFIELD_PASSWORD`.

O **primeiro boot demora** (uns 20 a 40 minutos): instala o ComfyUI e baixa dezenas de GB de modelos.
Enquanto isso, o link mostra uma página com o andamento. Nos próximos boots leva poucos minutos.

## Dicas

- **Pare o pod quando não estiver usando.** A GPU cobra por hora enquanto o pod está ligado;
  o volume cobra à parte (~US$ 0,07 por GB/mês) e guarda tudo.
- Se esquecer a senha (ou deixar `OPENFIELD_PASSWORD` vazio), ela aparece nos **Logs** do pod.
- Logs detalhados ficam em `/workspace/logs/` (`boot.log`, `comfyui.log`, `openfield.log`, `gate.log`).
- `OPENFIELD_SKIP_DOWNLOAD=1` liga sem conferir os modelos (boot mais rápido).

## Licenças dos modelos

- `ltx25`, `ltx-tools`: LTX-2.x Community License, uso comercial liberado abaixo de US$ 10 mi/ano de receita.
- `qwen`, `edit`: Apache 2.0. `cutout` (BiRefNet): MIT.
- Não incluídos de propósito: `h3` (licença exclui EUA, UE, Reino Unido e Coreia do Sul),
  `flux2` e `upres-ultrasharp` (não comerciais).

## Como funciona

O template usa a imagem `runpod/pytorch` e, no boot, roda o [`boot.sh`](boot.sh) deste repositório:
instala o OpenField num commit testado com o instalador oficial (`scripts/install.sh --yes`),
baixa os modelos para o volume e liga tudo. O OpenField não tem login próprio, então um pequeno
portão em Node (porta 3170) pede a senha e repassa para ele.

OpenField é de [wexloops/openfield](https://github.com/wexloops/openfield). Este repositório só automatiza a instalação no RunPod.

# My Open Dock

Um Dock alternativo para macOS, feito em SwiftUI e AppKit, com perfis, widgets e ocultação automática. Sem conta e sem servidor.

## Sobre este projeto

Fiz este app para mim, para usar no meu Mac. Ele foi inspirado no [Dockset](https://dockset.app/), mas é independente e não tem afiliação com ele.

O código está aberto para quem quiser usar como base: faça um fork e adapte do seu jeito. Issues e pull requests são bem-vindos, mas o projeto não é mantido ativamente. Pode demorar para eu responder, ou eu posso não responder.

O código é aberto sob a [licença MIT](LICENSE).

## Baixar

Abra a página de [Releases](https://github.com/guilhermelippert/my-open-dock/releases/latest), baixe o `.zip` mais recente, extraia e mova `My Open Dock.app` para a pasta Aplicativos. O pacote é para Macs com Apple Silicon e macOS 14 ou superior.

O aplicativo usa assinatura local ad hoc, sem Developer ID ou notarização da Apple. Se o macOS bloquear a abertura, confira a origem do download e use a opção de abertura em **Ajustes do Sistema > Privacidade e Segurança**.

## O que faz

- Perfis de Dock com aplicativos, arquivos, pastas, links, Atalhos do macOS e espaçadores.
- Barra flutuante com itens fixados e aplicativos em execução.
- Arraste os ícones da barra para mudar a ordem. Clique com o botão direito em um ícone ou na barra para ver as opções.
- Duração da animação ao aparecer e sumir, de 0 (instantâneo) a 1 segundo.
- Troca de perfil pela barra de menus, Control + Option + 1 a 9 ou Command + rolagem sobre a barra.
- Widgets de relógio, data, foco, bateria, notas, memória e carga do sistema, cronômetro, relógio mundial e hidratação.
- Posição embaixo, à esquerda ou à direita, tamanho dos ícones, aparência e ocultação automática.
- Redimensionamento da barra inteira de 60% a 160%, pela alça da barra ou pelo controle em **Aparência**. Apps, widgets e espaçadores acompanham a escala.
- Importação e exportação em JSON de perfis, preferências e conteúdo persistido dos widgets.
- Captura e aplicação dos itens fixados no Dock da Apple, com um ponto de restauração salvo antes da primeira troca.

Os perfis iniciais usam aplicativos encontrados no próprio Mac. A barra personalizada funciona ao lado do Dock da Apple. Aplicar um layout nativo altera os itens fixados, sem abrir ou fechar seus aplicativos.

## Compilar e instalar

Requisitos:

- Mac com Apple Silicon.
- macOS 14 ou superior.
- Command Line Tools da Apple com Swift, disponíveis com `xcode-select --install`.

Depois de obter o código, execute na pasta do projeto:

```sh
git clone https://github.com/guilhermelippert/my-open-dock.git
cd my-open-dock
bash scripts/build.sh
```

O aplicativo será criado em `build/My Open Dock.app`. Para instalá-lo em `~/Applications`:

```sh
bash scripts/build.sh --install
```

O instalador preserva uma cópia da versão anterior na pasta `build`, caso ela exista. Compilar e instalar não abre o aplicativo. Para abri-lo:

```sh
open "$HOME/Applications/My Open Dock.app"
```

O script atual compila somente para `arm64`.

## Usar

O ícone do aplicativo fica na barra de menus. Abra **Gerenciar Docks…** para editar perfis, adicionar itens e configurar a barra. Fechar o editor mantém a barra funcionando. Para encerrar o aplicativo, escolha **Sair do My Open Dock** no menu.

Em **Aparência**, você pode ocultar a barra e escolher se o aplicativo deve iniciar com a sessão. O início automático depende do registro permitido pelo macOS.

**Usar configuração do meu Dock** cria ou atualiza o perfil **Meu Dock** com os apps e pastas fixados no Dock da Apple, na mesma ordem, e copia tamanho dos ícones, posição e ocultação automática. Seus outros perfis continuam disponíveis. O Dock da Apple é apenas consultado.

Com **Ocultar automaticamente** ligado, a barra desaparece ao afastar o ponteiro e reaparece ao encostar na borda da tela. Em **Animação ao aparecer**, escolha quanto tempo ela leva para surgir e sumir. Com 0, é instantâneo. A opção de ocultar também está no menu de perfis e no clique direito da barra.

## Dados e backups

Os nomes internos (`DocksetLocal`, `local.gui.DocksetLocal`) ficam do nome antigo do projeto, para não perder dados de quem já usava. Os perfis ficam em `~/Library/Application Support/DocksetLocal/state.json`. Notas e preferências dos widgets usam o domínio local `local.gui.DocksetLocal` e entram nos backups exportados.

Importar um backup substitui os perfis e preferências atuais. Exporte antes se quiser preservá-los. O ponto de restauração do Dock da Apple permanece específico de cada Mac, mesmo ao importar um backup de outra máquina.

Se o arquivo de perfis não puder ser lido, o aplicativo guarda uma cópia de recuperação antes de permitir novas gravações. Os dados ficam no próprio Mac. Abrir links e executar Atalhos aciona os aplicativos correspondentes.

## Verificar

O smoke test usa uma pasta temporária para verificar persistência, edição de perfis e itens, limites, recuperação de arquivo inválido, importação transacional, backups de widgets e escala da barra. A captura do Dock nativo é somente leitura. O teste não aplica layouts ao Dock da Apple.

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  Sources/DocksetLocal/Core.swift Tests/CoreSmoke.swift \
  -o /tmp/dockset-core-smoke
/tmp/dockset-core-smoke
```

A alça de redimensionamento também tem um teste nativo que não exibe nenhuma janela:

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  Sources/DocksetLocal/Core.swift Sources/DocksetLocal/ResizeHandle.swift \
  Tests/ResizeSmoke.swift -o /tmp/dockset-resize-smoke
/tmp/dockset-resize-smoke
```

O layout compacto e a separação entre apps e pastas também são verificados:

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  Sources/DocksetLocal/Core.swift Sources/DocksetLocal/DockBarSizing.swift \
  Sources/DocksetLocal/Widgets.swift Tests/DockLayoutSmoke.swift -o /tmp/dockset-layout-smoke
/tmp/dockset-layout-smoke
```

## Limites atuais

Integrações com Stripe, Paddle, Shopify e contas de IA não estão implementadas. Também faltam previsão do tempo, controle de música, leitura de eventos e lembretes, automação por modo Foco do macOS e prévias de janelas.

O calendário mostra a data atual e abre o Calendário da Apple. A atividade do sistema mostra memória e carga média, não uso percentual de CPU. A barra usa o monitor principal.

A aplicação e a restauração de layouts no Dock da Apple estão implementadas, mas não fazem parte do smoke test automatizado. Não há garantia de equivalência completa com o Dockset original.

## Estrutura

- `Sources/DocksetLocal`: aplicativo, editor, persistência e widgets.
- `Resources`: metadados e ícone do aplicativo.
- `scripts/build.sh`: compilação, assinatura local e instalação opcional.
- `Tests/CoreSmoke.swift`: verificações do modelo e da persistência.
- `Tests/ResizeSmoke.swift`: arraste, limites, reset e acessibilidade da alça.

## Licença

[MIT](LICENSE), copyright 2026 guilhermelippert. A referência ao Dockset identifica o produto que inspirou o projeto e não implica parceria ou aprovação dos seus autores.

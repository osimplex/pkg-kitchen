# Processo de instalação do sistema de empacotamento

## Instalação do PowerShell Core

O PowerShell Core é um *software* livre, um *shell* multiplataforma, e é a base do sistema de empacotamento *pkg-kitchen*. Acessar a página de lançamento da última versão do PowerShell Core:
> https://github.com/PowerShell/PowerShell/releases/latest

Na página de lançamento buscar o *hiperlink* para o instalador Windows na arquitetura *64 bits*. Exemplo de referência: `PowerShell-<codigo de versao>-win-x64.msi`.

A última versão testada para o gerador é a 7.2.6 do PowerShell Core, que pode se obter no *hiperlink* abaixo:
> https://github.com/PowerShell/PowerShell/releases/download/v7.2.6/PowerShell-7.2.6-win-x64.msi

Salvo o arquivo do instalador, realizar o processo de instalação dando continuidade em trodas as etapas com as opções padrão. Para isso é necessário ter permissões de administardor.

## Instalação do módulo do sistema de empacotamento

Para instalar o módulo do sistema de empacotamento é necessário criar o diretório de módulos do PowerShell, que pode ser feito pelo próprio PowerShell com o seguinte comando:
```
PS C:\> New-Item -Type Directory $env:PSModulePath.Split(';')[0]
```

Criado o diretório de módulos, realizar a clonagem do repositório do sistema de empacotamento para o diretório de módulos do PowerShell.

## Preparação para uso da ferramenta

De saída, todas as operações do sistema de empacotamento tomam o repositório de controle de versão local `git` mapeado para um dispositivo, por padrão o dispositivo `<any>`. Mapear antes de qualquer operação.

Caso o dispositivo não esteja mapeado ocorrerá a seguinte interação:
```
PS C:\> Export-Package
Exception: Erro 51: <any> nao mapeado
```

Tendo o dispositivo mapeado, a primeira coisa a se fazer é a geração do dicionário de dependências:
```
PS C:\> Build-MdiDependenciesDB
```

Após isso, criar o diretório de destino dos artefatos gerados pelo sistema de empacotamento:
```
PS C:\> New-Item -Type Directory C:\artefatos
```

Após isso todas as operações possíveis de realizar com o sistema de empacotamento são possíveis.

# Casos de uso para empacotamento de artefato de teste

## Operação ensaiada

O modo de operação ensaiada se limita o utilitário a realizar os cálculos de diferença, apresentar o resultado e finalizar sem gerar qualquer artefato. Para utilizar o modo de operação ensaiada basta adicionar o parâmetro `-DryRun`, conforme o exemplo:
```
PS C:\> Export-Package -DryRun
```

## Geração de pacote de teste para demandas regulares

Para gerar um pacote de teste é necessário ter o controle de versão apontado para um ramo válido de demanda, prefixo *feature*, o que se pode conseguir com `git checkout feature/<cod_demanda>`. Após isso executar:
```
PS C:\> Export-Package
```

O comando produzirá um descritivo da diferença do ramo em relação à referência, por padrão o ramo *develop*, com listagem das MDIs determinadas para compilação com base no dicionário de dependências. Então serão iniciados os processos de compilação, criação de PDC e empacotamento conforme for determinada a necessidade. Os resultados serão depositados no diretório de artefatos, por padrão em `C:\artefatos`.

Para gerar o pacote compactado com o nome igual ao ID de uma solicitação na plataforma de chamados pode-se informar o parâmetro que determina o nome do arquivo *zip*, conforme o exemplo:
```
PS C:\> Export-Package -ZipName <ID de solicitação>
```

## Geração de pacote de teste para demandas do tipo hotfix com ramo criado a partir do main

O processo é muito similar ao descrito acima, é necessário apontar o controle de versão para o ramo da mesma forma, mas faz-se necessário mudar a referência do cálculo de diferença para determinação do pacote, conforme o exemplo:
```
PS C:\> Export-Package -VcsBaseTarget main
```

Desta forma a diferença do ramo será computada contra o estado do *main* no repositório local.

## Geração de pacote de teste para demandas após confluência no ramo de referência

Igualmente sem grandes diferenças de operação, só necessitando de alterar o cálculo de diferença, uma vez que depois de confluência, do *merge*, deixa de haver diferença computável pelo cálculo regular. Para computar a diferença de um ramo após confluência na referência é necessário informar o parâmetro `-FatherBased`:
```
PS C:\> Export-Package -FatherBased
```

## Inclusão arbitrária de MDIs no pacote de teste

Na mesma linha, para adicionar uma MDI nas tarefas de compilação para a geração do pacote de teste basta incluir o parâmetro `-Mdis`, seguido do nome de uma, ou de uma lista de nomes separados por vírgula, MDI seguindo os nomes que constam no catálogo:
```
PS C:\> Export-Package -Mdis A-Application
```

Ou:
```
PS C:\> Export-Package -Mdis A-Application, Another-Application
```

## Inclusão arbitrária de arquivos do controle de versão no pacote de teste

Muito semelhante ao processo de MDIs, bastando especificar o parâmetro `-IncludeFile` seguido do nome de um arquivo no controle de versão:
```
PS C:\> Export-Package -IncludeFile anyfilename.ext
```

Ou, utilizando a sintaxe de encadeamento do PowerShell, passar uma lista de nomes de arquivos a serem incluídos:
```
PS C:\> 'afile.ext', 'anotherfile.ext' | Export-Package
```

# Casos de uso para empacotamento de versão do produto

## Geração de pacote de atualização de versões antigas

A geração de pacotes de atualização anteriores pode ser feita com base nos etiquetamentos fixados no controle de versão, que indicam os estados representativos das versões do sistema a época de lançamento. Também pode ser realizado baseado na última revisão, na *cabeça*, dos ramos de geração de pacote de atualização, prefixo *release*. A preparação do apontamento do controle de versão pode se realizar com `git checkout <etiquetamento ou ramo de empacotamento>`.

O cálculo de diferença para geração de pacote de atualização exige um lógica própria, acionada com o parâmetro `-Release`. Também é necessário determinar a referência para o cálculo, caso realize-se o cálculo com o controle de versão apontado para um ramo de geração de pacote, prefixo *release*.

O exemplo que segue se aplica à geração do pacotes com o controle de versão apontado para uma revisão etiquetada:
```
PS C:\> Export-Package -Release
```

Já no caso do controle de versão apontado para um ramo de empacotamento, como a referência padrão para cálculo de diferença entre ramos é o *develop*, faz-se necessário determinar uma referência adequada ao caso de uso através do parâmetro `-VcsBaseTarget`, indicando-se tomar por referência sempre um etiquetamento que reflete a versão imediatamente anterior, conforme o exemplo:
```
PS C:\> Export-Package -VcsBaseTarget <etiquetamento> -Release
```

Os artefatos serão depositados por padrão em `C:\artefatos` como no processo de geração de pacote de teste.

## Geração de pacote de atualização para versões novas

Diferente de versões antigas, somente o ramo de empacotamento, prefixo *release*, está disponível, mas o processo é igual ao de geração de pacote de versões antigas, basta apontar o controle de versão para o ramo de empacotamento e passar o etiquetamento da versão imediatamente anterior como referência para o cálculo de diferença, conforme o mesmo exemplo:
```
PS C:\> Export-Package -VcsBaseTarget <etiquetamento> -Release
```

# Parâmetros especiais do gerador de pacote (comando Export-Package)

## -NoSetVersion

Durante a geração de pacote de atualização na orientação padrão de cálculo é realizada uma alteração no arquivo de versões de aplicação do sistema, à partir de um arquivo modelo. Para evitar que essa modificação seja realizada basta adicionar o parâmetro conforme o exemplo:
```
PS C:\> Export-Package -Release -NoSetVersion
```

## -NoPTF

Da mesma forma que o parâmetro `-NoSetVersion`, visa o cenário de geração de pacote de atualização na orientação padrão, da qual faz parte a tarefa de compilação do executável de PTF. Adicionando o parâmetro, a tarefa de compilação de aplicação PTF deixa de fazer parte do processo de empacotamento, conforme o exemplo:

```
PS C:\> Export-Package -Release -NoPTF
```

## -NoVersionUpdateScript

Como o parâmetro `-NoSetVersion`, visa o cenário de geração de pacote de atualização, independente da orientação de cálculo. Por padrão é construído um arquivo *pdc* com instruções para atualização da tabela de versões de acordo com o estado do arquivo de versões de aplicações do sistema no controle de versão. Para que esta etapa não seja realizada basta adicionar o parâmetro conforme o exemplo abaixo:
```
PS C:\> Export-Package -Release -NoVersionUpdateScript
```

## -Rollback

Este parâmetro só se aplica em cenário de geração de pacote de atualização e determina uma orientação de cálculo para que o produto do empacotamento não reflita o estado corrente dos arquivos determinados como diferentes, mas do estado destes arquivos tal no momento de fixação da referência indicada para a determinação da diferença.

Melhor explicando, por exemplo: ao invés de empacotar as diferenças com o estado de um ramo fictício `release/19.00.065`, para onde está apontado o controle de versão, empacotá-las no estado da *cabeça* do ramo *main*, ou de um etiquetamento da versão imediatamente anterior. Exemplificando o caso da *cabeça* do ramo *main*:
```
PS C:\> Export-Package -VcsBaseTarget main -Release -Rollback
```

E o etiquetamento de versão imediatamente anterior:
```
PS C:\> Export-Package -VcsBaseTarget 19.00.064 -Release -Rollback
```

## -Clean

Em especial nas operações de geração de pacote de atualização podem ser geradas modificações de alguns arquivos de interesse no processo de empacotamento. Para determinar que o controle de versão seja purgado desses arquivos após a conclusão da geração do pacote, pode-se adicionar o parâmetro `-Clean`, conforme o exemplo:
```
PS C:\> Export-Package -Clean -Release
```

Ou:
```
PS C:\> Export-Package -Clean -Release -Rollback
```

# Casos de uso para demais utilitários do sistema de empacotamento

## Geração de dicionário de dependências de MDIs do catálogo

O utilitário `Build-MdiDependenciesDB` sem parâmetros adicionais realiza uma varredura através repositório local sob controle de versão, à partir dos arquivos fonte das MDIs determinados no catálogo, e determina todas as dependências de cada MDI no catálogo, diretas e indiretas, consolidando um dicionário de dependência por MDI que é depositado em diretório temporário do usuário. Segue formato básico de utilização:
```
PS C:\> Build-MdiDependenciesDB
```

## Determinação de MDIs dependentes de uma dada aplicação

O utilitário `Get-MdisFromAplDepencies`, sempre seguido do parâmetro `-Apls` com um caminho, ou uma lista de caminhos separados por vírgula, de arquivos fonte de aplicações, determina todas as MDIs que dependem dos arquivos especificados. Segue exemplo:
```
PS C:\> Get-MdisFromAplDepencies -Apls '<any>:\absolute\path\to\file.ext'
```

Ou:
```
PS C:\> Get-MdisFromAplDepencies -Apls '<any>:\absolute\path\to\file.ext', '<any>:\another\absolute\path\to\file.ext'
```

## Compilação de MDI avulsa

O utilitário `Build-Mdi` é capaz de realizar a compilação de qualquer MDI informada, depositando por padrão o executável resultante no diretório `C:\<any>` com o nome igual ao atribuído na propriedade `Object` do catálogo de MDIs. O comando de compilação sempre deve vir acompanhado ao menos do parâmetro indicando um nome de MDI conforme consta no catálogo, na forma do exemplo:
```
PS C:\> Build-Mdi -Mdi A-Application
```

Também é possível atribuir sufixos aos nomes dos executáveis compilados adicionando o parâmetro `-BinSufix`:
```
PS C:\> Build-Mdi -Mdi Another-Application -BinSufix feature_eval_123
```

Bem como alterar o caminho de destino do executável compilado adicionando o parâmetro `-BinPath`:
```
PS C:\> Build-Mdi -Mdi Max-Venda -BinPath 'C:\compilados'
```

## Limpeza de resíduos de compilação de MDIs

O utilitário `Clear-TempBuildDir` é dedicado à tarefa de limpeza dos arquivos residuais de compilação de MDIs, que ficam depositados em um diretório temporário do usuário. A consulta deste diretório pode ser realizada com o comando:
```
PS C:\> Get-ChildItem (Join-Path $env:TMP 'pkg_kitchen_builds')
```

Para efetuar a limpeza deste diretório, que pode consumir bastante espaço de armazenamento em disca, há um utilitário que usa-se conforme o exemplo:
```
PS C:\> Clear-TempBuildDir
```

## Consulta de código de versões de MDIs

O utilitário `Get-SystemVersion` sem parâmetros adicionais retorna uma lista de todas as MDIs no catálogo com as respectivas versões conforme o estado do arquivo de versões:
```
PS C:\> Get-SystemVersion
```

Para obter uma lista ordenada da mais antiga para a mais recente pode-se processar a saída conforme o exemplo:
```
PS C:\> (Get-SystemVersion)?.GetEnumerator() | Sort-Object Value, Key
```

Para obter versões de aplicações específicas basta informar o parâmetro `-Mdis` seguido de um nome, ou de uma lista de nomes separados por vírgula, de MDI da qual se deseje obter a versão, conforme exemplo:
```
PS C:\> Get-SystemVersion -Mdis A-Application
```

Ou:
```
PS C:\> Get-SystemVersion -Mdis A-Application, Another-Application
```

## Alteração de código de versões de MDIs

O utilitário `Set-SystemVersion` é capaz de realizar a manipulação e reescrita do estado do arquivo de versões, onde são determinados os códigos de versão de cada aplicação do sistema bem como o código de versão do sistema, sempre igual ao código de versão da aplicação mais recente.

Dado o conjunto de possibilidades, aconselha-se a leitura do manual *detalhado* do comando que pode ser consultado com o comando `Get-Help` do PowerShell, na forma apresentada abaixo:
```
PS C:\> Get-Help Set-SystemVersion -Detailed
```

A utilização mais básica, complementar para algumas ocasiões de compilação de MDI avulsa que precise de versão que reflita um registro na tabela de versões, conta com o parâmetro `-Mdis` seguido de um nome, ou de uma lista de nomes separados por vírgula, de MDIs que se deseja alterar o respectivo código de versão.

Para determinar a versão `27.00.012`:
```
PS C:\> Set-SystemVersion -Mdis A-Application -Year 27 -Version 012
```

Ou:
```
PS C:\> Set-SystemVersion -Mdis A-Application, Another-Application -Year 27 -Version 012
```

# Consulta de manuais e utilitários do sistema de empacotamento

Os utilitários do sistema de empacotamento contam com manuais acessíveis através do comando `Get-Help` do PowerShell, conforme o exemplo abaixo:
```
PS C:\> Get-Help Export-Package -Detailed
```

Para consultar todos os utilitários do sistema de empacotamento utilizar o seguinte comando:
```
PS C:\> (Get-Module Build-Package -ListAvailable).ExportedCommands.Values
```

# Considerações sobre os cálculos de diferença entre ramos

Os cálculos de diferença que determinam a tarefa de empacotamento são baseados no estado do repositório local, não do repositório remoto.

Dito isso, enumero alguns cenários que podem devolver resultados que podem não corresponder à necessidade do usuário:
 1. Ramo de referência desatualizado em relação à revisão de criação do corrente (atualmente apontado no controle de versão);
 2. Ramo de referência com revisões posteriores à base de criação do ramo corrente de trabalho.

No caso do cenário 1 o resultado do cálculo potencialmente devolverá maior quantidade de alterações do que foi efetivamente realizado, e todas serão empacotadas igualmente. Para garantir que o cálculo seja assertivo e alinhado com a expectativa é recomendado manter o ramo usado como referência de cálculo atualizado, seja o *develop* que é referência padrão, seja o *main* ou outro ramo informado por parâmetro `-VcsBaseTarget`.

No cenário 2 o cálculo regular pode igualmente devolver maior quantidade de alterações do que foi efetivamente realizado, se o ramo não estiver baseado sobre a *cabeça*, sobre a última revisão do ramo de referência. Estando baseado em revisão anterior à *cabeça* do ramo de referência haverá a seguinte interação:
```
PS C:\> Export-Package
Exception: Erro 53: Ramo desatualizado em relacao ao develop ou pos-merge
```

Isso pode ser tratado de duas formas:
 1. Alterando o cálculo de diferença. O cálculo apropriado para esse contexto é o de diferença simétrica entre os ramos, que pode se aplicar através do parâmetro `-SimmetricDiff`, ex.: `Export-Package -SimmetricDiff`. Esse modo de cálculo não se aplica para geração de pacotes de atualização.
 2. Mudando a base do ramo corrente em relação à referência no controle de versão. Ver `git rebase --help`. Dado o potencial da operação, utilizar com prudência e dar preferência à mudança do cálculo de diferença.

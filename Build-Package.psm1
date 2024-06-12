# Parâmetros padrão ----------------------------------------

# Arquivo padrão de versões
$defaultVcsVersionFile = '<Caminho relativo ao SCV do arquivo de versoes>'

# Aplicação padrão para PTF (Program Temporary Fix)
$defaulPtfApplication = '<Nome da aplicação auxilizar de PTF>'

# Dispositivo padrão de SCV (git)
$defaultVcsDevice = '<Dispositivo Windows mapeado para o diretorio do SCV>'

# Ramo padrão no SCV
$defaultVcsBaseTarget = 'develop'

# Diretório padrão de destino de artefatos
$defaultArtDir = 'c:\artefatos'

# Nome padrão para diretório de objetos do banco (que serão unidos num arquivo de tipo PDC)
$defaultPdcSourceDirName = '<Nome do diretorio sem caminho>'

# Prioridade padrão para processos do compilador
$defaultCompilingProcessPriority = [System.Diagnostics.ProcessPriorityClass]::Normal

# Argumentos padrão para a linha de comando de compilação
$defaultCompilerArgs = '<args>'

# Compilador padrão de aplicações
$defaultCompiler = '<Caminho absoluto para executavel do compilador>'

# Diretório temporário padrão para aplicações compiladas
$defaultTempBuildDir = 'pkg_kitchen_builds'

# Diretório padrão de destino de compilados avulsos
$defaultBinPath = '<Caminho absoluto de diretorio>'

# Arquivos de base de dados --------------------------------

# Local para base de dependencias de MDIs (Multiple-document interface)
$dependenciesDB = Join-Path $env:TMP 'pkg_kitchen_mdi_deps.json'

# Local para catalogo de aplicações
$catalogoPath = Join-Path $env:PSModulePath.Split(';')[0] 'pkg-kitchen/catalogo.json'

# Classes --------------------------------------------------

# Classe de validação de parâmetro Mdis
Class MdiSet : System.Management.Automation.IValidateSetValuesGenerator {

    [String[]] GetValidValues() {

        $catalogoPath = Join-Path $env:PSModulePath.Split(';')[0] 'pkg-kitchen/catalogo.json'
        $MdiSet = @((Get-Content $catalogoPath | ConvertFrom-Json -AsHashtable).Keys)

        return [String[]] $MdiSet

    }

}

# Funções auxiliares ---------------------------------------

# Função de tratamento de erro
$die = {

    if (! $args[0]) { '' ; throw $args[1] }

}

# Função de captura e resposta a Ctrl-C
$scriptBlockOnCtrlC = {

    $inputKey = if ([System.Console]::KeyAvailable) { [System.Console]::ReadKey($true) }

    if (($inputKey.Modifiers -band [System.ConsoleModifiers]::Control) -and
        ($inputKey.Key -band [System.ConsoleKey]::C)) {

        & $args[0]
        $args[1].Value = $true

    }

}

# Comandos PowerShell --------------------------------------

<#
.SYNOPSIS
  Utilitario para recuperacao de versoes de MDIs do sistema

.DESCRIPTION
  Este utilitario verifica o arquivo de versões padrao no dispositivo padrao e
  recupera as versoes determinadas para cada aplicacao do sistema.

.PARAMETER AsVersionUpdateScript
  O resultado do processamento de versoes deve estar no formato de atualizacao
  da tabela de versões em SQL.

.PARAMETER UpdateScriptPath
  Caminho de destino do script de atualizacao da tabela de versoes.

.PARAMETER Mdis
  Aplicacoes que terao a versao e data de lancamento alteradas.

.PARAMETER VcsDevice
  Local do sistema de controle de versao (SCV git).

.PARAMETER VcsVersionFile
  Caminho relativo ao VcsDevice para o arquivo de versoes.

#>
function Get-SystemVersion {

    param(
        [Switch] $AsVersionUpdateScript,

        [ValidateNotNullOrEmpty()]
        [String] $UpdateScriptPath,

        [Parameter(
            ValueFromPipeline
        )]
        [ValidateSet([MdiSet])]
        [ValidateNotNullOrEmpty()]
        [String[]] $Mdis,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice,

        [ValidateNotNullOrEmpty()]
        [String] $VcsVersionFile = $defaultVcsVersionFile
    )

    # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
    Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
    & $die $? "Erro 51: $VcsDevice nao mapeado"

    # As operações de conversão dependem da existência do arquivo de versão
    $versionFile = Join-Path ($VcsDevice + ':\') $VcsVersionFile | `
        Get-Item -ErrorAction SilentlyContinue
    & $die $? "Erro 74: $VcsVersionFile nao existe"

    # Recuperar catálogo de informações de MDI
    $catalogo = Get-Content $catalogoPath 2> $null | ConvertFrom-Json -AsHashtable
    & $die $? 'Erro 74: Catalogo de informacoes de MDIs nao existe'

    # A exportação de script necessita de um caminho absoluto de destino declarado
    & $die (! ($AsVersionUpdateScript -xor $UpdateScriptPath)) `
        'Erro 59: A geracao de arquivo de atualizacao necessita de um caminho de destino'
    & $die (! $UpdateScriptPath -or (Split-Path $UpdateScriptPath -IsAbsolute)) `
        'Erro 63: Destino de script especificado como caminho relativo'

    # Garantir consistência de parâmetros e pipeline
    $changes = @($input ? $input : $Mdis).Where({ $_ -ne $defaulPtfApplication })

    # Construção de segmento de expressão regular para recuperação de versões das MDIs
    $versionCodes = ($changes ? $changes : $catalogo.Keys) | ForEach-Object {

        $versionCode =
            (! $catalogo.$_.VersionDate) ?
            $catalogo.$_.VersionCode + '_VS' :
            $catalogo.$_.VersionCode
        [regex]::escape($versionCode)

    }
    $versionCodes = '(' + ($versionCodes -join '|') + ')'

    # Efetiva expressão regular de recuperação de versão de MDI
    $regexVersion = [regex] "^\..*:\s+$versionCodes =\s*'?((\d{2,3}\.?){3})'?\s*$"

    # Codificação do arquivo de versão
    $encWindows = [System.Text.Encoding]::GetEncoding("windows-1252")

    # Criação do operador de leitura
    $versionReader = New-Object System.IO.StreamReader -ArgumentList ($versionFile, $encWindows)

    while ($versionReader.Peek() -ge 0) {

        $line = $versionReader.ReadLine()
        $versionMatch = $line | Select-String $regexVersion

        if (! $versionMatch) { continue }

        $mdiVersions += @{$catalogo.Keys.Where({

            ($versionMatch.Matches.Groups[1].Value -Replace '_VS$', '') -eq
            ($catalogo.$_.VersionCode -Replace '_VS$', '') -and
            $_ -ne $defaulPtfApplication

        })[0] = $versionMatch.Matches.Groups[2].Value}

    }

    # Fechamento do operador de leitura
    $versionReader.Close()

    if ($AsVersionUpdateScript) {

        # Arquivo temporário para escrita
        $tempScriptFile = New-Item -Type File `
            (Join-Path $env:TMP "version_update_script-$([System.Guid]::NewGuid().ToString()).temp")
        $null > $tempScriptFile

        # Alocação de construtor do texto do arquivo de atualização com 4 KiB
        $versionTableText = New-Object System.Text.StringBuilder -ArgumentList (1024 * 4)

        # Cabeçalho do arquivo de operações de atualização da tabela de versões
        $versionTableText.
            AppendLine('PROMPT VERSION PDC ---------------- Inicio ----------------').
            AppendLine() > $null

        # Escrita das operações de atualização
        $mdiVersions.Keys.ForEach({

            $versionTableText.
                AppendLine("-- Aplicacao $_").
                AppendLine('UPDATE schema.tabela m').
                AppendLine("   SET m.versao = '$($mdiVersions.$_)'").
                AppendLine(" WHERE m.sistema = '$($catalogo.$_.DBSystem)'").
                AppendLine("   AND m.modulo = '$($catalogo.$_.DBModule)';").
                AppendLine() > $null

        })

        # Linha de persistência das alterações
        $versionTableText.
            AppendLine("-- Persistir alteracoes").
            AppendLine("COMMIT;").
            AppendLine() > $null

        # Rodapé do arquivo de operações de atualização da tabela de versões
        $versionTableText.
            AppendLine('PROMPT VERSION PDC ---------------- Concluido ----------------') > $null

        # Escrita do arquivo de atualização da tabela de versões
        $versionTableText.ToString() > $tempScriptFile

        Move-Item -Force $tempScriptFile $UpdateScriptPath -ErrorAction SilentlyContinue
        & $die $? 'Erro 231: Arquivo de operações de atualizacao em uso por outro processo'

    } else { $mdiVersions }

}

<#
.SYNOPSIS
  Utilitario para definicao de versoes de MDIs do sistema

.DESCRIPTION
  Este Utilitario realiza a reconstrucao de trechos do arquivo de versoes de
  modo a refletir uma nova versao e/ou data intencionada, seja informada via
  linha de comando explicitamente ou por disposicao no SCV seguindo a convencao
  de lancamento de versao do sistema.

.PARAMETER DryRun
  Realizar somente os calculos de alteracao de versao e data.

.PARAMETER Release
  Determinar calculos com base em referencia no SCV para lancamento de versao.

.PARAMETER FromModel
  Usar como base o arquivo de versao do modulo PS.

.PARAMETER SystemStep
  Realizar os calculos para modificar versao do sistema.

.PARAMETER Version
  Valor da primeira parte do codigo de versao no formato "Year.Part.Version".

.PARAMETER Part
  Valor da segunda parte do codigo de versao no formato "Year.Part.Version".

.PARAMETER Year
  Valor da terceira parte do codigo de versao no formato "Year.Part.Version".

.PARAMETER Date
  Data de lancamento da versao no formato "dd/MM/yyyy".
  A data de lancamento padrao sera a o dia corrente.

.PARAMETER Mdis
  Aplicacoes que terao a versao e/ou data de lancamento alteradas.

.PARAMETER VcsDevice
  Local do sistema de controle de versao (SCV git).

.PARAMETER VcsVersionFile
  Caminho relativo ao parametro VcsDevice para o arquivo de versoes.
 #>
function Set-SystemVersion {

    param(
        [Switch] $DryRun,

        [Switch] $Release,

        [Switch] $FromModel,

        [Switch] $SystemStep,

        [ValidatePattern('\d{3}')]
        [ValidateNotNullOrEmpty()]
        [String] $Version,

        [ValidatePattern('\d{2}')]
        [ValidateNotNullOrEmpty()]
        [String] $Part,

        [ValidatePattern('\d{2}')]
        [ValidateNotNullOrEmpty()]
        [String] $Year,

        [ValidateScript({
            [DateTime]::ParseExact($_, 'dd/MM/yyyy', $null)
        })]
        [ValidateNotNullOrEmpty()]
        [String] $Date = (Get-Date -Format dd/MM/yyyy),

        [Parameter(
            ValueFromPipeline
        )]
        [ValidateSet([MdiSet])]
        [ValidateNotNullOrEmpty()]
        [String[]] $Mdis,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice,

        [ValidateNotNullOrEmpty()]
        [String] $VcsVersionFile = $defaultVcsVersionFile
    )

    # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
    Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
    & $die $? "Erro 51: $VcsDevice nao mapeado"

    # Argumento em CLI do git determinando o caminho do SCV
    $gitDir = "-C ${VcsDevice}:\".Split(' ')

    # Modelo de arquivo de versão
    $versionModel = Join-Path $env:PSModulePath.Split(';')[0] 'pkg-kitchen/versoes.template' |
        Get-Item -ErrorAction SilentlyContinue
    & $die $? 'Erro 74: Modelo de arquivo de versao nao existe'

    # Recuperar catálogo de informações de MDI
    $catalogo = Get-Content $catalogoPath 2> $null | ConvertFrom-Json -AsHashtable
    & $die $? 'Erro 74: Catalogo de informacoes de MDIs nao existe'

    <#
     # Parâmetros para construção do arquivo de versão do sistema
     #>
    $versionFile = Join-Path ($VcsDevice + ':\') $VcsVersionFile |
        Get-Item -ErrorAction SilentlyContinue
    & $die $? "Erro 74: $VcsVersionFile nao existe"

    # Garantir consistência entre parâmetro e pipeline
    $changes = @($input ? $input : $Mdis).Where({ $_ -ne $defaulPtfApplication })

    # Assegurar objetivo de operação
    & $die ($SystemStep -or ($changes)) 'Erro 22: Sem objetivo de calculo definido'

    # Arquivo temporário para escrita
    $tempVersionFile = New-Item -Type File `
        (Join-Path $env:TMP "system_version_file-$([System.Guid]::NewGuid().ToString()).temp")
    $null > $tempVersionFile

    # Arquivo de referência para o cálculo
    $sourceFile = $versionFile
    if ($FromModel) { $sourceFile = $versionModel }
    & $die $sourceFile 'Erro 213: Arquivo de referencia nao existe'

    # Definição dos componentes do código de versão
    & $die (! (($Year -or $Part -or $Version) -and $Release)) `
        'Erro 185: Duplicidade de determinacao de versao'

    if ($Release) {

        # Recuperação do objetivo corrente no SCV
        $gitCurrentTarget = git $gitDir branch --show-current
        $gitCurrentTarget ??= 'release/' + (git $gitDir describe --exact-match 2> $null)

        # Objetivos de cálculo incoerentes com a base de cálculo não serão executados
        & $die ($gitCurrentTarget -Match 'release/') `
            'Erro 76: Incongruencia entre objetivo e modo de determinacao de versao'

        # Decomposição do código de versão no objetivo
        $codeRegex = [regex] '^(\d{2})\.(\d{2})\.(\d{3})(\.\d{1,2})?$'
        $code = @(($gitCurrentTarget.Split('/')[1] |
            Select-String $codeRegex).Matches.Groups?[1..3].Value)
        & $die $code 'Erro 157: Falha na decomposicao do codigo de versao'

    } else { $code = $Year, $Part, $Version }

    # Codificação do arquivo de versão
    $encWindows = [System.Text.Encoding]::GetEncoding("windows-1252")

    # Operadores de leitura e escrita
    $versionReader = New-Object System.IO.StreamReader -ArgumentList ($sourceFile, $encWindows)
    $versionWriter = New-Object System.IO.StreamWriter -ArgumentList ($tempVersionFile, $encWindows)

    # Construção das expressões regulares das linhas de data e versão
    if ($changes) {

        $versionCodes = $changes | ForEach-Object {

            $versionCode =
                (! $catalogo.$_.VersionDate) ?
                $catalogo.$_.VersionCode + '_VS' :
                $catalogo.$_.VersionCode
            [regex]::escape($versionCode)

        }
        $versionCodes = '(' + ($versionCodes -join '|') + ')'

        $versionDates = $changes | ForEach-Object {

            $dateCode =
                (! $catalogo.$_.VersionDate) ?
                $catalogo.$_.VersionCode + '_DT' :
                $catalogo.$_.VersionDate
            [regex]::escape($dateCode)

        }
        $versionDates = '(' + ($versionDates -join '|') + ')'

        $regexVersion = [regex] "^(\..*:\s+)($versionCodes =\s*'?)((\d{2,3}\.?){3})('?\s*)$"
        $regexDate = [regex] "^(\..*:\s+)($versionDates =\s*'?)((\d{2}/|\d{4}){3})('?\s*)$"

    }

    # Construção das expressões para versão do sistema
    $systemPtf = 'PTFApplicationVersionIdInFile'
    $systemVersion = 'SystemVersionIdInFile'
    $regexSystemPtf = [regex] "^(\..*:\s+)(($systemPtf) =\s*'?)(\d{3})('?\s*)$"
    $regexSystemVersion = [regex] "^(\..*:\s+)(($systemVersion) =\s*'?)((\d{2}\.?){2})('?\s*)$"

    # Construtor de mensagem de status
    $stateMessage = {

        $args[0], $args[1].Matches.Groups?[3].Value, $args[2] | Join-String -Separator ' '

    }

    # Controle de sucesso nas iterações
    [Bool[]] $check = $true
    [String] $stderr = $null

    while ($versionReader.Peek() -ge 0) {

        $line = $versionReader.ReadLine()

        # Realizar casamento
        $versionMatch = ($changes) ? ($line | Select-String $regexVersion) : $null
        $dateMatch = ($changes) ? ($line | Select-String $regexDate) : $null
        $systemPtfMatch = ($SystemStep) ? ($line | Select-String $regexSystemPtf) : $null
        $systemVersionMatch = ($SystemStep) ? ($line | Select-String $regexSystemVersion) : $null

        # Registrar erro se houve casamento simultâneo e pular iteração
        if ($versionMatch -and $dateMatch) {

            $check += $false
            $stderr = 'Erro 200: casamento simultâneo de padrão de data e versão'
            $versionWriter.WriteLine($line)
            continue

        }

        if ($systemVersionMatch) {

            ''
            $prefix = $systemVersionMatch.Matches.Groups?[1].Value
            $symbol = $systemVersionMatch.Matches.Groups?[2].Value
            $sufix = $systemVersionMatch.Matches.Groups?[6].Value

            $decomposedNumber = @($systemVersionMatch.Matches.Groups?[4].Value?.Split('.'))
            $oldNumber = $decomposedNumber | Join-String -Separator '.'
            & $stateMessage 'system-version-old:' $systemVersionMatch $oldNumber

            if (! [String]::IsNullOrWhiteSpace($code[0])) { $decomposedNumber.SetValue($code[0], 0) }
            if (! [String]::IsNullOrWhiteSpace($code[1])) { $decomposedNumber.SetValue($code[1], 1) }
            $number = $decomposedNumber | Join-String -Separator '.'
            if ($oldNumber -ne $number) {

                & $stateMessage 'system-version-new:' $systemVersionMatch $number
                $check += $true

            }

            $line = $prefix, $symbol, $number, $sufix | Join-String

        }

        if ($systemPtfMatch) {

            ''
            $prefix = $systemPtfMatch.Matches.Groups?[1].Value
            $symbol = $systemPtfMatch.Matches.Groups?[2].Value
            $sufix = $systemPtfMatch.Matches.Groups?[6].Value

            $oldNumber = $systemPtfMatch.Matches.Groups?[4].Value
            & $stateMessage 'system-ptf-old:' $systemPtfMatch $oldNumber

            $number = ($code[2]) ? $code[2] : $oldNumber
            if ($oldNumber -ne $number) {

                & $stateMessage 'system-ptf-new:' $systemPtfMatch $number
                $check += $true

            }

            $line = $prefix, $symbol, $number, $sufix | Join-String

        }

        if ($versionMatch) {

            ''
            $prefix = $versionMatch.Matches.Groups?[1].Value
            $symbol = $versionMatch.Matches.Groups?[2].Value
            $sufix = $versionMatch.Matches.Groups?[6].Value

            $decomposedNumber = @($versionMatch.Matches.Groups?[4].Value?.Split('.'))
            $oldNumber = $decomposedNumber | Join-String -Separator '.'
            & $stateMessage 'version-old:' $versionMatch $oldNumber

            if (! [String]::IsNullOrWhiteSpace($code[0])) { $decomposedNumber.SetValue($code[0], 0) }
            if (! [String]::IsNullOrWhiteSpace($code[1])) { $decomposedNumber.SetValue($code[1], 1) }
            if (! [String]::IsNullOrWhiteSpace($code[2])) { $decomposedNumber.SetValue($code[2], 2) }
            $number = $decomposedNumber | Join-String -Separator '.'
            if ($oldNumber -ne $number) {

                & $stateMessage 'version-new:' $versionMatch $number
                $check += $true

            }

            $line = $prefix, $symbol, $number, $sufix | Join-String

        }

        if ($dateMatch) {

            ''
            $prefix = $dateMatch.Matches.Groups?[1].Value
            $symbol = $dateMatch.Matches.Groups?[2].Value
            $sufix = $dateMatch.Matches.Groups?[6].Value

            $oldNumber = $dateMatch.Matches.Groups?[4].Value
            & $stateMessage 'date-old:' $dateMatch $oldNumber

            $number = (($code[0] -or $code[1] -or $code[2]) -and $Date) ? $Date : $oldNumber
            if ($oldNumber -ne $number) {

                & $stateMessage 'date-new:' $dateMatch $number
                $check += $true

            }

            $line = $prefix, $symbol, $number, $sufix | Join-String

        }

        $versionWriter.WriteLine($line)

    }

    # Fechamento dos operadores de leitura e escrita
    $versionWriter.Flush()
    $versionWriter.Close()
    $versionReader.Close()

    # Impedimento de persistência dos resultados em caso de DryRun
    if ($DryRun) { $check += $false ; $stderr = 'Erro 199: Parametro DryRun habilitado' }

    # Qualquer registro de erro anula a matriz de validação
    if ($check.Length -eq 1) { $check = $false ; $stderr = 'Erro 205: Nao alterou-se versao' }
    else { foreach ($item in $check) {

        if (! $item) {

            $check = $false
            $stderr ??= 'Erro 207: Falha no processo de registro'
            break

        }

    }}
    # Ou ausência de registro de erro ou sucesso
    if (! $check) { Remove-Item -Force $tempVersionFile }
    & $die $check $stderr

    Move-Item -Force $tempVersionFile $versionFile -ErrorAction SilentlyContinue
    & $die $? 'Erro 210: Arquivo de versao do sistema em uso por outro processo'

}

function Build-Pdc {

    param(
        [Parameter (
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String] $PdcComponent,

        [ValidateNotNullOrEmpty()]
        [String] $PdcPath,

        [String] $PdcPrefix,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice
    )

    begin {

        # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
        Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
        & $die $? "Erro 51: $VcsDevice nao mapeado"

        # Preparacao do diretório de destino
        if (! (Test-Path $PdcPath -PathType Container)) {

            New-Item $PdcPath -Type Directory -ErrorAction SilentlyContinue > $null
            & $die $? "Erro 74: $PdcPath ou conteudo em uso por outro processo"

        }

        # Controle de eventos de escrita
        $pdcWritingControl = $false

        # Definição de destino para objetos individuais
        $plsqlObjectsPath = Join-Path $pdcPath 'database_object'
        New-Item $plsqlObjectsPath -Type Directory -ErrorAction SilentlyContinue > $null
        & $die $? "Erro 74: $plsqlObjectsPath ou conteudo em uso por outro processo"

        # Definição de arquivo de PDC
        $pdcObject = Join-Path $PdcPath `
            ((($PdcPrefix) ? $PdcPrefix + '_' : $null) + (Split-Path -Leaf $PdcPath) + '.pdc').ToLower()

        # Codificação para leitura e escrita
        $encWindows = [System.Text.Encoding]::GetEncoding("windows-1252")

        # Criação do operador de escrita
        try {

            $pdcWriter = New-Object System.IO.StreamWriter -ArgumentList ($pdcObject, $encWindows)

        } catch {

            throw "Erro 87: $pdcObject sem possibilidade de associar ao operador de escrita"

        }
        & $die $pdcWriter "Erro 98: Arquivo de destino do pdc nulo"

        # Escrita do cabeçalho do arquivo PDC
        $pdcWriter.WriteLine("PROMPT PDC ---------------- Inicio ----------------")
        $pdcWriter.WriteLine("")

    }


    process {

        # Previsão para contração de PDC em cenário de pacote de recuperação
        $warning = $null
        Copy-Item $PdcComponent $plsqlObjectsPath -Force -ErrorAction SilentlyContinue
        $warning = ($?) ? $null : ": nao existe"
        "  - $(Split-Path -Leaf $PdcComponent)$warning"

        if (! $warning) {

            # Criação do operador para o processo de leitura do objeto
            $pdcReader = New-Object System.IO.StreamReader -ArgumentList ($PdcComponent, $encWindows)

            # Escrita do cabeçalho de objeto no arquivo PDC
            $pdcWriter.WriteLine("PROMPT")
            $pdcWriter.WriteLine("PROMPT Compilando $(Split-Path -Leaf $PdcComponent) ----------------")
            $pdcWriter.WriteLine("PROMPT")
            $pdcWriter.WriteLine("")

            # Todas as linhas com caracteres não "brancos" serão escritas no PDC
            while ($pdcReader.Peek() -ge 0) {

                $line = $pdcReader.ReadLine().TrimEnd()
                if (! [String]::IsNullOrWhiteSpace($line)) { $pdcWriter.WriteLine($line) }

            }

            $pdcWriter.WriteLine("/")
            $pdcWriter.WriteLine("")

            # Fechamento do operador de leitura do objeto
            $pdcReader.Close()

            # A ocorrência de eventos de escrita deve ser registrada
            $pdcWritingControl = $true

        }

    }

    end {

        # Escrita do rodapé do arquivo PDC e fechamento dos operadores de escrita
        $pdcWriter.WriteLine("PROMPT PDC ---------------- Concluido ----------------")

        $pdcWriter.Flush()
        $pdcWriter.Close()

        # Limpar diretório de trabalho se não houve escrita
        if (! $pdcWritingControl) {

            $pdcObject, $plsqlObjectsPath | Remove-Item  -Force -ErrorAction SilentlyContinue

        }

    }

}

<#
.SYNOPSIS
  Utilitario para limpeza de residuos de compilacao

.DESCRIPTION
  Condicao de funcionamento:

  Todos os arquivos no diretorio temporario padrao para objetos de compilacao
  serao apagados.
#>
function Clear-TempBuildDir {

    $tempBuildDir = Join-Path $env:TMP $defaultTempBuildDir
    $cleanTargets = Get-ChildItem $tempBuildDir -ErrorAction SilentlyContinue

    if ($cleanTargets -and (Test-Path $tempBuildDir -PathType Container)) {

        $cleanTargets | Remove-Item -Recurse -ErrorAction SilentlyContinue

    }

}

function Build-MdiByName {

    param(
        [Parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String] $Mdi,

        [ValidateNotNullOrEmpty()]
        [String] $BinPath = $defaultBinPath,

        [String] $BinSufix,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice
    )

    begin {

        # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
        Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
        & $die $? "Erro 51: $VcsDevice nao mapeado"

        # O compilador deve estar especificado em caminho absoluto
        & $die ((Test-Path $defaultCompiler -PathType Leaf) -and
                (Split-Path $defaultCompiler -IsAbsolute)) `
            'Erro 90: Compilador especificado nao existe, ou especificado em caminho relativo'

        # Recuperar catálogo de informações de MDI
        $catalogo = Get-Content $catalogoPath 2> $null | ConvertFrom-Json -AsHashtable
        & $die $? 'Erro 74: Catalogo de informacoes de MDIs nao existe'

        # Preparacao do diretório de destino
        if (! (Test-Path $BinPath -PathType Container)) {

            New-Item $BinPath -Type Directory -ErrorAction SilentlyContinue > $null
            & $die $? "Erro 74: $BinPath ou conteudo em uso por outro processo"

        }

        # Alocação de estrutura para controle de processo
        $process = New-Object System.Diagnostics.Process

    }

    process {

        "  - $($catalogo.$Mdi.Object)"

        $binObject = Join-Path (Get-Item $BinPath) (
            ($BinSufix.Trim().Length -gt 0) ?
            $catalogo.$Mdi.Object + '-' + $BinSufix + '.exe' :
            $catalogo.$Mdi.Object + '.exe')
        $mdiPath = Join-Path ($VcsDevice + ':\') $catalogo.$Mdi.Path

        $tempBuildDir = Join-Path $env:TMP $defaultTempBuildDir

        # Garantia do diretório temporário de compilados
        if (! (Test-Path $tempBuildDir -PathType Container)) {

            New-Item $tempBuildDir -Type Directory -ErrorAction SilentlyContinue > $null
            & $die $? "Erro 74: $tempBuildDir ou conteudo em uso por outro processo"

        }

        # Destino temporário de compilação
        $tempObject = New-Item -Type File `
            (Join-Path $tempBuildDir "temp-$([System.Guid]::NewGuid().ToString()).temp")

        # Construção dos argumentos para a linha de comando do compilador
        $compilingArgs = ($defaultCompilerArgs + ' ' + $mdiPath + ' ' + $tempObject)

        # Definição de parâmetros para o processo, disparo, tratamento e liberação de recursos
        try {

            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $defaultCompiler
            $processInfo.Arguments = $compilingArgs
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $false

            $process.StartInfo = $processInfo
            $process.Start() > $null
            $process.PriorityClass = $defaultCompilingProcessPriority
            $process.WaitForExit()

        } catch {

            throw "Erro 10: Compilacao de $mdiPath nao realizada"

        } finally {

            $process.Close()

            Remove-Item ((Join-Path ($VcsDevice + ':\') $catalogo.$Mdi.Path) -Replace '.app', '.err') `
                -ErrorAction SilentlyContinue
            & $die (! $?) "Erro 11: Compilacao de $mdiPath apresentou erro"

            Copy-Item -Force $tempObject $binObject -ErrorAction SilentlyContinue
            & $die $? "Erro 75: $binObject em uso por outro processo"

        }

    }

    end {

        # Desalocação de todos os recursos utilizados pelo controle do processo
        $process.Dispose()

    }

}

<#
.SYNOPSIS
  Utilitario para construcao de executavel do sistema

.DESCRIPTION
  Este utilitario realiza a compilacao dos executaveis do sistema.

.PARAMETER Mdi
  Aplicacao que sera compilada.

.PARAMETER BinPath
  Diretorio destino do binario construido.
  c:\pkg_kitchen_bin e o diretorio padrao.

.PARAMETER BinSufix
  Sufixo para o nome do executavel gerado.

.PARAMETER VcsDevice
  Local do sistema de controle de versao (SCV git).
 #>
function Build-Mdi {

    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline
        )]
        [ValidateSet([MdiSet])]
        [ValidateNotNullOrEmpty()]
        [String] $Mdi,

        [ValidateNotNullOrEmpty()]
        [String] $BinPath = $defaultBinPath,

        [ValidateNotNullOrEmpty()]
        [String] $BinSufix,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice
    )

    $Mdi | Build-MdiByName `
        -BinPath $BinPath -BinSufix $BinSufix -VcsDevice $VcsDevice

}

<#
.SYNOPSIS
  Utilitario para determinar relacoes de dependencias

.DESCRIPTION
  Este utilitario realiza o levantamento automatizado do conjunto de arquivos
  fonte do qual depende um dado arquivo fonte de aplicacao arbitrariamente
  informado por argumento em linha de comando.

.PARAMETER Recurse
  Determinar dependencias diretas e indiretas da aplicacao.

.PARAMETER Apl
  Aplicacao que sera base de calculo de dependencia.

.PARAMETER VcsDevice
  Local do sistema de controle de versao (SCV git).
#>
function Get-Dependencies {

    param(
        [Switch] $Recurse,

        [Parameter(
            ValueFromPipeline
        )]
        [ValidateNotNullOrEmpty()]
        [String] $Apl,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice
    )

    # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
    Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
    & $die $? "Erro 51: $VcsDevice nao mapeado"

    # Preparação da base de cálculo
    $aplPath = Join-Path ($VcsDevice + ':\') $Apl
    & $die (Test-Path $aplPath -PathType Leaf) "Erro 74: $aplPath nao existe ou nao e um arquivo"

    # Base de pesquisa de dependência
    $regexInclude = [regex] "^(\s+|.*-?\s+[^!]\s+)Include: (.*)(\s+)?$"

    # Preparar variáveis de trabalho
    $dependencies = @($aplPath.ToLower())
    $children = $aplPath

    # Realizar cálculo de dependências
    do {

        $previousCount = $dependencies.Count

        $children = $(foreach ($dep in (Select-String -Path $children $regexInclude)) {

                Join-Path ($VcsDevice + ':\') $dep.Matches.Groups[3].Value.ToLower()

            }) | Sort-Object -Unique

        $dependencies = @($dependencies + $children | Sort-Object -Unique)

    } while ($Recurse -and $dependencies.Count -ne $previousCount)

    # Retornar o resultado
    $dependencies

}

<#
.SYNOPSIS
  Utilitario para gerar dicionario de dependencias de MDIs

.DESCRIPTION
  Este utilitario realiza a consolidacao de uma base de dependencias para MDIs
  catalogada, utilizando o calculo recursivo baseado nos arquivos fontes de
  cada aplicacao.

.PARAMETER Threads
  Numero maximo de tarefas paralelas de determinacao de dependencias.

.PARAMETER VcsDevice
  Local do sistema de controle de versao (SCV git).
#>
function Build-MdiDependenciesDB {

    param(

        [ValidateNotNullOrEmpty()]
        [Int] $Threads = ([System.Math]::Floor($env:NUMBER_OF_PROCESSORS / (1 + 1 / 3))),

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice

    )

    # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
    Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
    & $die $? "Erro 51: $VcsDevice nao mapeado"

    # Recuperar catálogo de informações de MDI
    $catalogo = Get-Content $catalogoPath 2> $null | ConvertFrom-Json -AsHashtable
    & $die $? 'Erro 74: Catalogo de informacoes de MDIs nao existe'

    # Base para registro de dependências e estado do cálculo
    $database = [System.Collections.Concurrent.ConcurrentDictionary[string, array]]::New()
    $currentMdis = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::New()

    # Delimitação do número de linhas de execução, entre 1 e o número máximo de tarefas
    $throttleLimit = ($Threads -le 1) ? 1 :
        (($Threads -gt $catalogo.Keys.Count) ? $catalogo.Keys.Count : $Threads)

    # Tarefa em plano de fundo para os cálculos de dependência
    $calculatorJob = $catalogo.Keys | ForEach-Object -Parallel {

        $proxyDB = $using:database
        $proxyCatalogo = $using:catalogo
        $proxyCurrentMdis = $using:currentMdis

        $proxyCurrentMdis.TryAdd($_, 0) > $null
        $dependencies = @(Get-Dependencies -Recurse `
            -VcsDevice $using:VcsDevice $proxyCatalogo.$_.Path)
        $proxyDB.TryAdd($_, $dependencies) > $null
        $proxyCurrentMdis.TryRemove($_, [ref] $null) > $null

    } -ThrottleLimit $throttleLimit -UseNewRunspace -AsJob

    # Acionar a possibilidade de tratamento do Ctrl-C para término limpo do processo
    $previousTreatControlCAsInput = [System.Console]::TreatControlCAsInput
    [System.Console]::TreatControlCAsInput = $true

    $cancelledOperation = $false

    # Apresentação de status e controle de execução
    while ($calculatorJob.State -eq 'Running') {

        Start-Sleep -Milliseconds 500

        $progressStatus = $currentMdis.Keys -join ', '

        if ($progressStatus -ne $progressStatusOld -and $progressStatus) {

            Write-Progress -Activity 'Calculando dependencias' `
                -Status $progressStatus `
                -PercentComplete ($database.Count / $catalogo.Keys.Count * 99 + 1)

        }

        $progressStatusOld = $progressStatus

        & $scriptBlockOnCtrlC { Stop-Job $calculatorJob > $null } ([ref] $cancelledOperation)

    }

    # Registro condicional do dicionário de dependências
    if (! $cancelledOperation) {

        # Determinar destino do registro de dependências
        $DBPath = New-Item -Type File $dependenciesDB -Force -ErrorAction SilentlyContinue
        & $die $? "Erro 74: $DBPath em uso por outro processo"

        # Persistência do registro de dependências
        ConvertTo-Json $database > $DBPath

    }

    # Retorno à condição anterior de tratamento do Ctrl-C
    [System.Console]::TreatControlCAsInput = $previousTreatControlCAsInput

}

<#
.SYNOPSIS
  Utilitario para determinacao de MDIs dependentes de aplicacoes

.DESCRIPTION
  Este utilitario determina as MDIs catalogadas que dependem de um dado arquivo
  fonte de aplicacao arbitrariamente informado por argumento em linha de
  comando.

.PARAMETER Apls
  Aplicacoes que serao a base de determinacao de MDIs dependentes.
#>
function Get-MdisFromAplDepencies {

    param (
        [Parameter(
            ValueFromPipeline
        )]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]] $Apls
    )

    # O dicionário de dependencias deve estar posicionado
    Get-Item $dependenciesDB -ErrorAction SilentlyContinue > $null
    & $die $? "Erro 39: registro de dependencias nao existe"

    # Recuperação do dicionário de dependências
    $dependenciesDict = Get-Content $dependenciesDB | ConvertFrom-Json -AsHashtable

    # Garantir consistência entre parâmetro e pipeline
    $aplTargets = ($input ? $input : $Apls).ForEach({ $_ -replace '/', '\' })

    # Todo caminho especificado para a determinação de MDI dependente deve estar
    # especificado na forma absoluta, e deve haver ao menos um caminho válido
    & $die (! $aplTargets.Where({

        ! (Split-Path $_ -IsAbsolute)

    })) 'Erro 93: todo caminho deve estar especificado na forma absoluta'
    & $die $aplTargets.Where({

        Split-Path $_ -IsAbsolute

    }) 'Erro 94: sem caminhos validos para determinacao de dependencias'

    # Determinação de MDIs que dependem das aplicações informadas
    $mdiTargets += @(foreach ($maybeDep in $aplTargets.ToLower()) {

        @($dependenciesDict.Keys).Where({

            $_ -ne $defaulPtfApplication -and
            $dependenciesDict.$_.IndexOf($maybeDep) -ge 0

        })

    }) | Sort-Object -Unique

    $mdiTargets

}

function Get-BranchDiff {

    param(
        [Bool] $FatherBased,

        [Bool] $SimmetricDiff,

        [ValidateNotNullOrEmpty()]
        [String[]] $GitDir,

        [String] $Branch,

        [Ref] $Base
    )

    # Captura de commit irmão pós criação do ramo
    $firstSibling = @(

        git $GitDir rev-list --first-parent $('^' + $Branch) $Base.Value

    )[-1]

    & $die ($SimmetricDiff -or $FatherBased -or ! $firstSibling) `
        "Erro 53: Ramo desatualizado em relacao ao $($Base.Value) ou pos-merge"

    # Definição da base de comparação do estado do ramo
    if ($FatherBased) {

        $gitBaseForBranch = git $GitDir log -1 --pretty=%H $($firstSibling + '^') 2> $null

    } else { $gitBaseForBranch = $Base.Value }
    & $die @($gitBaseForBranch) 'Erro 54: Sem base para calculo de diff'

    if ($FatherBased) {

        # Recuperação do registro de modificações
        $branchLog = @(git $GitDir log --pretty=%H $($gitBaseForBranch + '..' + $Branch))
        & $die $branchLog "Erro 55: Nenhuma alteracao no ramo $Branch"

        # Determinação dos arquivos modificados
        $firstCommit = git $GitDir rev-parse "$($branchLog[-1])~"
        $diffNames = @(git $GitDir diff --name-only HEAD..$firstCommit)

        # Atualizar referência para base de cálculo
        $Base.Value = $firstCommit

    } else {

        # Determinação do operador de cálculo de diferença
        $diffOperator = ($SimmetricDiff) ? '...' : '..'

        # Determinação dos arquivos modificados
        $diffNames = @(git $GitDir diff --name-only $($Base.Value + $diffOperator + $Branch))
        & $die $diffNames "Erro 55: Nenhuma alteracao no ramo $Branch"

        # Atualizar referência para base de cálculo
        $Base.Value = git $GitDir rev-parse $Base.Value

    }

    # Retornar o resultado
    $diffNames

}

function Get-ReleaseDiff {

    param(
        [ValidateNotNullOrEmpty()]
        [String[]] $GitDir,

        [String] $Target,

        [Ref] $Base
    )

    # Especificar bases de cálculo por etiquetamento ou por ramo
    if ((git $GitDir branch --show-current) -ne $Target) {

        $auxTarget = $Target.Split('/')[1]

        # Recuperação do registro de etiquetamento
        $tags = @(git $GitDir tag --sort=-version:refname)
        $tags = $tags[1..($tags.Length - 1)]

        # As âncoras de cálculo devem constar nos registros
        & $die ($tags.IndexOf($auxTarget) -ge 0) `
            "Erro 175: SCV nao apontado para um estado de lancamento"

        # Definição da base de comparação do estado de etiquetamento
        $gitBaseForTarget = $tags[($tags.IndexOf($auxTarget) + 1)]

    } else { $auxTarget = $Target ; $gitBaseForTarget = $Base.Value }

    # Determinação dos arquivos modificados
    $diffNames = @(git $GitDir diff --name-only $($gitBaseForTarget + '..' + $auxTarget))

    # Retornar o resultado e atualizar referência para base de cálculo
    $Base.Value = git $GitDir rev-parse $gitBaseForTarget
    $diffNames

}

<#
.SYNOPSIS
  Utilitario para geracao de pacotes

.DESCRIPTION
  Este utlilitário reúne todas as operações necessárias para a geração de um
  pacote de teste ou atualização do sistema.

  Apos uma execucao com exito havera um diretorio com os artefatos nos caminhos
  (de acordo com os ramos no SCV):

    - Feature c:\artefatos\feature\id_do_ramo\
    - Hotfix  c:\artefatos\hotfix\id_do_ramo\
    - Epic    c:\artefatos\epic\id_do_ramo\
    - Release c:\artefatos\release\cod_versao\

.PARAMETER DryRun
  Realizar somente os calculos de modificacao para o objetivo de empacotamento.

.PARAMETER Clean
  Realizar a limpeza do diretório de trabalho do SCV pre e pos empacotamento.
  Qualquer modificacao fora de revisao ou da area de rascunho e eliminada.

.PARAMETER NoInteractive
  Nao solicitar confirmacoes nem interacao do usuario.

.PARAMETER FatherBased
  Gerar pacote para um ramo comparado contra a revisao originaria.

.PARAMETER SimmetricDiff
  Gerar pacote baseado na diferenca simetrica de um ramo contra o base.

.PARAMETER Release
  Gerar pacote de lancamento de versao para um objetivo de calculo no SCV.

.PARAMETER Rollback
  Gerar pacote de recuperacao para um objetivo de calculo no SCV.

.PARAMETER NoPTF
  Nao realizar a compilacao da aplicacao PTF.

.PARAMETER NoSetVersion
  Nao modificar o arquivo de versoes das aplicacoes do sistema.

.PARAMETER NoVersionUpdateScript
  Nao realizar a geracao do arquivo PDC de atualizacao da tabela de versões.

.PARAMETER NoPdc
  Nao gerar PDC nem copiar objetos para o pacote.

.PARAMETER NoQrp
  Nao copiar arquivos QRP (visualizador de relatórios) para o pacote.

.PARAMETER NoMdi
  Nao compilar aplicacoes para o pacote.

.PARAMETER NoZip
  Nao realizar o empacotamento de artafatos.

.PARAMETER Threads
  Numero maximo de tarefas paralelas de compilacao de aplicacoes.

.PARAMETER ArtDir
  Caminho absoluto de diretorio base para geracao de pacote.

.PARAMETER Mdis
  Lista adicional e arbitrária de MDIs para compilar e incluir no pacote.

.PARAMETER ZipName
  Nome do arquivo compactado de artefatos.
  Por padrao o zip recebe o nome do ramo no SCV.

.PARAMETER IncludeFile
  Arquivos arbitrarios no SCV para incluir no pacote.

.PARAMETER VcsDevice
  Local do sistema de controle de versao (SCV).

.PARAMETER VcsBaseTarget
  Ramo de referencia no sistema de controle de versao (SCV git).
#>
function Export-Package {

    param(
        [Switch] $DryRun,

        [Switch] $Clean,

        [Switch] $NoInteractive,

        [Switch] $FatherBased,

        [Switch] $SimmetricDiff,

        [Switch] $Release,

        [Switch] $Rollback,

        [Switch] $NoPTF,

        [Switch] $NoSetVersion,

        [Switch] $NoVersionUpdateScript,

        [Switch] $NoPdc,

        [Switch] $NoQrp,

        [Switch] $NoMdi,

        [Switch] $NoZip,

        [ValidateNotNullOrEmpty()]
        [Int] $Threads = ([System.Math]::Floor($env:NUMBER_OF_PROCESSORS / (1 + 1 / 3))),

        [ValidateNotNullOrEmpty()]
        [String] $ArtDir = $defaultArtDir,

        [ValidateSet([MdiSet])]
        [ValidateNotNullOrEmpty()]
        [String[]] $Mdis,

        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Name')]
        [ValidateNotNullOrEmpty()]
        [String] $IncludeFile,

        [ValidateNotNullOrEmpty()]
        [String] $ZipName,

        [ValidateNotNullOrEmpty()]
        [String] $VcsDevice = $defaultVcsDevice,

        [ValidateNotNullOrEmpty()]
        [String] $VcsBaseTarget = $defaultVcsBaseTarget
    )

    begin {

        # Todas as operações são realizadas partindo do dispotivivo mapeado para o SCV
        Get-Psdrive $VcsDevice -ErrorAction SilentlyContinue > $null
        & $die $? "Erro 51: $VcsDevice nao mapeado"

        # Argumento em CLI do git determinando o caminho do SCV
        $gitDir = "-C ${VcsDevice}:\".Split(' ')

        # Garantia de não contaminação do objetivo de cálculo
        & $die (! @(git $gitDir ls-files --others --exclude-standard)) `
            'Erro 83: Objetivo no controle de versao com arquivos nao controlados'
        & $die (! @(git $gitDir diff --name-only HEAD) -or $Clean) `
            'Erro 83: Objetivo no controle de versao com alteracao sem commit'

        # Recuperação do objetivo corrente no SCV
        $gitCurrentTarget = git $gitDir branch --show-current
        $gitCurrentTarget ??= 'release/' + (git $gitDir describe --exact-match 2> $null)

        # Objetivos de cálculo sem prefixo não são executados
        & $die ($gitCurrentTarget -Match '/') 'Erro 57: Objetivo sem prefixo'

        # A geração do artefato exige um ramo de história caso não seja atualização
        $historyBranchRegex = [regex] '^(feature|hotfix|epic)'
        & $die ($gitCurrentTarget -Match $historyBranchRegex -xor $Release) `
            'Erro 52: Incongruencia entre objetivo e modo de calculo de pacote'
        & $die ($gitCurrentTarget -Match $historyBranchRegex -or $Release) `
            'Erro 52: Ramo develop/master ou invalido'

        # As orientações de cálculo de diferenca são mutuamente excludendetes e nenhuma
        # se aplica em cálculo de pacote de atualização, mas a orientação de cálculo de
        # pacote de recuperação somente se aplica para o modo de pacote de atualização
        & $die (! ($FatherBased -and $SimmetricDiff)) `
            'Erro 52: Duplicidade de orientacao de calculo'
        & $die (! (($FatherBased -or $SimmetricDiff) -and $Release)) `
            'Erro 52: Incongruencia entre modo de calculo e orientacao de calculo'
        & $die (! ($SimmetricDiff -and $Rollback)) `
            'Erro 52: Pacote de recuperacao sera referenciado em estado potencialmente invalido'
        & $die ($Release -or ! $Rollback) `
            'Erro 52: Geracao de pacote de recuperacao em modo inapropriado de calculo'

        # Os parâmetros de ignora tanto do processo de ajuste do arquivo de versão como de
        # de geração de atualização da tabela de versões se aplicam somente no processo de
        # geração de pacote de atualização
        & $die ($Release -or ! ($NoSetVersion -or $NoVersionUpdateScript)) `
            'Erro 52: Impedimento de operacao de versao nao aplicavel ao modo de calculo'
        & $die (! ($Rollback -and $NoSetVersion)) `
            'Erro 52: Impedimento de alteracao de versao nao aplicavel a orientacao de calculo'

        # O parâmetro de ignora de compilação de aplicação PTF é aplicável somente ao
        # cálculo de geração de pacote de atualização na orientação básica
        & $die ($Release -or ! $NoPTF) `
            'Erro 52: Impedimento de compilacao de PTF nao aplicavel ao modo de calculo'
        & $die (! ($Rollback -and $NoPTF)) `
            'Erro 52: Impedimento de compilacao de PTF nao aplicavel a orientacao de calculo'

        # A referência para base de cálculo deve constar nos registros
        & $die ((git $gitDir show-ref refs/heads/$VcsBaseTarget) -or
                ($Release -and (git $gitDir show-ref refs/tags/$VcsBaseTarget))) `
            "Erro 176: $VcsBaseTarget nao consta no registro de referencias para o calculo"

        # O diretório de artefatos deve, além de existir, ser descrito em caminho absoluto
        & $die ((Test-Path $ArtDir -PathType Container) -and (Split-Path $ArtDir -IsAbsolute)) `
            "Erro 47: $ArtDir nao existe, nao e um diretorio ou nao e um caminho absoluto"

        # O dicionário de dependencias deve estar posicionado
        Get-Item $dependenciesDB -ErrorAction SilentlyContinue > $null
        & $die $? "Erro 39: registro de dependencias nao existe"

        # Arquivo de versão que deve ser descontado do cálculo de dependência
        $versionFile = (Join-Path ($VcsDevice + ':\') $defaultVcsVersionFile).ToLower()

        # Construção de expressão regular à partir de uma matriz de arquivos
        $regexFromListBuilder = {

            $resultRegEx = $args[0] | ForEach-Object { [regex]::escape($_) }
            '(' +  ($resultRegEx -join '|') + ')'

        }

        <#
         # Recuperação e segmentação dos arquivos alterados no ramo
         #>

        # Limpeza do diretório de trabalho do controle de versão
        if ($Clean) { git $gitDir reset --hard 2>&1 > $null }

        # Recuperação dos arquivos modificados
        $gitCurrentBase = $VcsBaseTarget
        $diffNames = $(if ($Release) {

            Get-ReleaseDiff -GitDir $gitDir `
                -Target $gitCurrentTarget -Base ([ref] $gitCurrentBase)

        } else {

            Get-BranchDiff -GitDir $gitDir `
                -FatherBased $FatherBased -SimmetricDiff $SimmetricDiff `
                -Branch $gitCurrentTarget -Base ([ref] $gitCurrentBase)

        })

        # Reversão do estado dos arquivos modificados para o estado da base de cálculo
        if ($Rollback) { foreach ($diff in $diffNames) {

            git $gitDir restore $diff --source=$gitCurrentBase 2> $null

        }}

        # Processamento de arquivos alterados no ramo
        $diffFiles = @($diffNames).ForEach({ Join-Path ($VcsDevice + ':\') $_ })

        # Determinação de RegEx para cada tipo de arquivo modificado
        $pdcSourceDirs = Get-ChildItem -Recurse -Directory $gitDir[1] |
            Where-Object Name -EQ $defaultPdcSourceDirName
        $pdcSourceDirsRegex = & $regexFromListBuilder $pdcSourceDirs.FullName

        $binFilesRegex = [regex] '\.(app|source|or|library|extension)$'
        $qrpFilesRegex = [regex] '\.qrp$'

        # Classificação de modificações
        $otherFiles = @($diffFiles).Where({

            $_ -NotMatch $binFilesRegex -and
            $_ -NotMatch $qrpFilesRegex -and
            $_ -NotMatch $pdcSourceDirsRegex

        })
        $pdcFiles = @($diffFiles).Where({ $_ -Match $pdcSourceDirsRegex })
        $qrpFiles = @($diffFiles).Where({ $_ -Match $qrpFilesRegex })
        $binFiles = @($diffFiles).Where({ $_ -Match $binFilesRegex })

        # Determinação de executáveis para compilar
        $binTargets = $binFiles.Where({ $_.ToLower() -ne $versionFile })
        $mdiTargets = ($binTargets) ? (Get-MdisFromAplDepencies -Apls $binTargets) : $null
        $mdiTargets = @($mdiTargets) + $Mdis +
            (($Release -and ! $Rollback -and ! $NoPTF) ? $defaulPtfApplication : $null) |
            Sort-Object -Unique

        # Divisão entre tipos de arquivos alterados no ramo
        $gitCurrentTarget
        ""
        @{
            other = @($otherFiles);
            pdc = @($pdcFiles);
            bin = @($binFiles);
            qrp = @($qrpFiles);
            mdi = @($mdiTargets)
        } | ConvertTo-Json

        if ($DryRun -and $Rollback -and $Clean) {

            git $gitDir reset --hard 2>&1 > $null
            git $gitDir clean -fdq

        }

        # Em caso de DryRun não realizar as construções de artefatos para o pacote
        & $die (! $DryRun) 'Erro 199: Parametro DryRun habilitado'

        # Construção de caminho de destino de artefatos e pacote
        $targetDir = Join-Path $ArtDir $gitCurrentTarget

        # Mensagens relativas ao processo de reversão
        if ($Rollback) {

            # Somente pode ser gerado o pacote de recuperação para um pacote gerado
            & $die (Test-Path $targetDir -PathType Container) 'Erro 74: Nao houve geracao de pacote'
            $targetDir = Join-Path $targetDir `
                "rollback-$($gitCurrentBase.Substring(0, 8))_$($gitCurrentTarget.Replace('/', '+'))"

            ''
            "Gerando pacote de recuperacao para o estado da rev. $($gitCurrentBase.Substring(0, 8))"

        }

        # Encerra-se um processo sem artefatos a empacotar
        if (($NoPdc -or ! ($pdcFiles)) -and
            ($NoQrp -or ! ($qrpFiles)) -and
            ($NoMdi -or ! ($mdiTargets)) -and
            (! ($included))) {

            ''
            throw 'Erro 230: Sem elementos para empacotar'

        }

        # É requisitada uma confirmação de continuidade caso já exista um destino de artefatos
        if ((Test-Path $targetDir -PathType Container) -and ! $NoInteractive) {

            ''
            Read-Host -Prompt 'Artefatos existentes no destino, Ctrl-C para interromper' > $null
            & $die $? 'Erro 199: Processo de empacotamento interrompido'

        }

        # Criação do diretório dos artefatos
        Remove-Item $targetDir -Recurse -ErrorAction SilentlyContinue
        New-Item $targetDir -Type Directory -ErrorAction SilentlyContinue > $null
        & $die $? "Erro 74: $targetDir ou conteudo em uso por outro processo"

    }

    process {

        # Inclusão de arquivos arbitrários no pacote de teste
        if (! [String]::IsNullOrWhiteSpace($IncludeFile)) {

            ""
            $incFile = Get-ChildItem -Path $gitDir[1] -Recurse -File -Include $IncludeFile

            if ($incFile) {

                "Adicionando $($incFile.FullName)"
                Copy-Item $incFile $targetDir -Force -ErrorAction SilentlyContinue
                & $die $? "Erro 121: $incFile em $targetDir em uso por outro processo"
                $included = $true

            }
            else {

                "Erro 254: $IncludeFile nao existe no controle de versao"

            }

        }

    }

    end {

        # Geração dos artefatos
        if (! $NoPdc -and $pdcFiles) {

            ""
            "Construcao de PDC:"
            $pdcFiles | Build-Pdc -PdcPath $targetDir `
                -PdcPrefix (($Release) ? 'ptf' : $null) -VcsDevice $VcsDevice

        }
        if (! $NoQrp -and $qrpFiles) {

            ""
            "Inclusao de QRP:"
            foreach ($qrpFile in $qrpFiles) {

                Copy-Item $qrpFile $targetDir -Force -ErrorAction SilentlyContinue
                $warning = ($?) ? $null : ": nao existe ou em uso por outro processo no destino"
                "  - $qrpFile$warning"

            }

        }
        if (! $NoMdi -and $mdiTargets) {

            ""
            "Construcao de EXE:"

            # Determinação de objetivos próprios para operações relativas a versão
            $versionTargets = $mdiTargets.Where({ $_ -ne $defaulPtfApplication })

            # Modificação das versões de aplicações determinadas para pacote de atualização
            if (! $Rollback -and ! $NoSetVersion -and $Release -and $versionTargets) {

                $mdiTargets | Set-SystemVersion -SystemStep -Release -FromModel > $null

            }

            # Geração do arquivo de atualização da tabela de versões
            if (! $NoVersionUpdateScript -and ($Release -or $Rollback) -and $versionTargets) {

                $mdiTargets | Get-SystemVersion -AsVersionUpdateScript `
                    -UpdateScriptPath (Join-Path $targetDir 'version_table_update.pdc')

            }

            # Acionar a possibilidade de tratamento do Ctrl-C para término limpo do processo
            $previousTreatControlCAsInput = [System.Console]::TreatControlCAsInput
            [System.Console]::TreatControlCAsInput = $true

            # Base para registro de dependências e estado do cálculo
            $compilingException = [System.Collections.Concurrent.ConcurrentStack[string]]::New()

            # Delimitação do número de linhas de execução, entre 1 e o número máximo de tarefas
            $throttleLimit = ($Threads -le 1) ?
                1 : (($Threads -gt $mdiTargets.Count) ? $mdiTargets.Count : $Threads)

            # Tarefa em plano de fundo para as compilações de MDIs
            $compilerJob = $mdiTargets | ForEach-Object -Parallel {

                $proxyCompilingException = $using:compilingException

                try {

                    Build-MdiByName -Mdi $_ -BinPath $using:targetDir -VcsDevice $using:VcsDevice

                } catch { $proxyCompilingException.TryAdd($PSItem.Exception.Message) > $null }

            } -ThrottleLimit $throttleLimit -UseNewRunspace -AsJob

            # Recuperação de mensagens e controle de execução
            while ($compilerJob.State -eq 'Running') {

                Start-Sleep -Milliseconds 500

                if ($compilingException.Count -gt 0) {

                    $exception = $null
                    $compilingException.TryPop(([ref] $exception)) > $null
                    Write-Error $exception

                }

                $changes = $compilerJob | Receive-Job
                if ($changes) { $changes.Split('`n').Where({ ! [String]::IsNullOrWhiteSpace($_) }) }

                & $scriptBlockOnCtrlC {

                    $compilerProcesses = Get-CimInstance `
                        -ClassName Win32_Process `
                        -Filter "ParentProcessId = $PID AND Name = '$($defaultCompiler.Split('\')[-1])'"

                    $compilerProcesses | Invoke-CimMethod -MethodName Terminate > $null
                    Stop-Job $compilerJob > $null

                } ([ref] $null)

            }

            # Retorno à condição anterior de tratamento do Ctrl-C
            [System.Console]::TreatControlCAsInput = $previousTreatControlCAsInput

        }
        if (! $NoZip -and @(Get-ChildItem $targetDir)) {

            ""
            "Empacotando e compactando artefato"
            $zipPath = ($ZipName) ?
                (Join-Path $targetDir $ZipName) + '.zip' :
                (Join-Path $targetDir (Split-Path -Leaf $targetDir).ToLower()) + '.zip'
            Compress-Archive $targetDir $zipPath -CompressionLevel Optimal

        } else {

            ''
            throw 'Erro 230: Sem elementos para empacotar'

        }

        # Restauração do estado do controle de versão
        if ($Clean) { git $gitDir reset --hard 2>&1 > $null }
        if ($Rollback) { git $gitDir clean -fdq }

    }

}

# Fim ------------------------------------------------------

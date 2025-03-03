@{

	RootModule = 'Build-Package.psm1'
	ModuleVersion = '1.0'
	GUID = 'adccce1e-7823-4011-9cd5-f83d16ab93b4'
	Author = 'Ordinatio Simplex'
	Copyright = '(c) Ordinatio Simplex. Todos os direitos reservados.'
	Description = 'Estudo de integração contínua com ênfase em software legado'

	FunctionsToExport = @(
		'Export-Package',
		'Build-Mdi',
		'Build-MdiByName',
		'Clear-TempBuildDir',
		'Get-MdisFromAplDepencies',
		'Build-MdiDependenciesDB',
		'Get-Dependencies',
		'Set-SystemVersion',
		'Get-SystemVersion'
	)

	FileList = @(
		'Build-Package.psd1',
		'Build-Package.psm1',
		'catalogo.json',
		'versoes.template'
	)

	CmdletsToExport = @()
	VariablesToExport = @()
	AliasesToExport = @()

}

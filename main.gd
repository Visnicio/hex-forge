extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not DirAccess.dir_exists_absolute("user://tilesets"):
		# Cria a pasta (e qualquer subpasta necessária)
		var erro = DirAccess.make_dir_recursive_absolute("user://tilesets")
		
		if erro == OK:
			print("Pasta 'user://tilesets' criada com sucesso!")
		else:
			printerr("Erro ao criar a pasta. Código: ", erro)
	else:
		print("A pasta 'user://tilesets' já existe.")
	
	#copy_base_files("res://resources/tilesets/example_tileset.tres", "user://tilesets/example_tileset.tres")


func copy_base_files(base_file: String, target_file: String) -> void:
	# 1. Verifica se o arquivo de origem realmente existe
	if not FileAccess.file_exists(base_file):
		printerr("Erro: Arquivo de origem não encontrado: ", base_file)
		return

	# 2. Verifica se o diretório de destino existe. Se não, cria.
	# Isso é importante se você estiver salvando em "user://saves/arquivo.json"
	var target_dir = base_file.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var erro_dir = DirAccess.make_dir_recursive_absolute(target_dir)
		if erro_dir != OK:
			printerr("Erro ao criar diretório: ", error_string(erro_dir))
			return

	# 3. Executa a cópia
	var erro = DirAccess.copy_absolute(base_file, target_file)
	
	if erro == OK:
		print("Sucesso! Arquivo copiado para: ", target_file)
	else:
		printerr("Falha ao copiar o arquivo. Código de erro: ", erro)

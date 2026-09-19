class_name TShader
extends RefCounted
## The shader composition of Engine.GfxApi.pas TShader (LoadShader, ParseBlocks, ApplyBlocks): a base shader with
## named sections `#block name` ... `#endblock` whose content the block files of the mesh's custom shaders (the mesh
## effects) replace; `#inherited` in a block stands for the content it replaces. Read docs/assets.md ("Mesh effects").
##
## Order (LoadShader): the block files are walked last to first; a file's block takes the place of `#inherited` in
## the same block collected so far, so the first file's block is outermost and the last file's sits closest to the
## base; ApplyBlocks then puts the base's own section content where `#inherited` is left. As in the original, a line
## holding "#block" anywhere starts a block and one holding "#endblock" ends it; nested blocks are not supported.

## Port: the original's shader files -> the ported block files (lower-case file name, .gdshaderinc).
const EFFECT_SHADER_ROOT := "res://src/runtime/graphics/effect_shaders/"

static var _file_cache := {}


## TShader.ParseBlocks: block name -> content (lines kept with their line breaks). Block names lose spaces and
## line breaks (tabs stay, as written; ApplyBlocks also drops tabs).
static func ParseBlocks(BlockString: String) -> Dictionary:
	var result := {}
	var block := ""
	var blockcontent := ""
	for raw_line in BlockString.split("\n"):
		var line := raw_line.replace("\r", "")
		if line.contains("#block"):
			if block != "":
				push_error("TShader.ParseBlocks: Nested blocks currently not supported!")
			block = line.replace("#block", "").replace(" ", "")
			blockcontent = ""
		elif line.contains("#endblock"):
			if block == "":
				push_error("TShader.ParseBlocks: Block closed, but not opened!")
			if result.has(block):
				push_error("TShader.ParseBlocks: duplicate block %s" % block)  # TDictionary.Add raises
			result[block] = blockcontent
			block = ""
			blockcontent = ""
		elif block != "":
			blockcontent += line + "\n"
	return result


## TShader.ApplyBlocks: the base with each section replaced by its block (`#inherited` = the section's content).
static func ApplyBlocks(ShaderString: String, Blocks: Dictionary) -> String:
	var result := ""
	var block := ""
	var blockcontent := ""
	for raw_line in ShaderString.split("\n"):
		var line := raw_line.replace("\r", "")
		if line.contains("#block"):
			if block != "":
				push_error("TShader.ApplyBlocks: Nested blocks currently not supported!")
			block = line.replace("#block", "").replace(" ", "").replace("\t", "")
			blockcontent = ""
		elif line.contains("#endblock"):
			if block == "":
				push_error("TShader.ApplyBlocks: Block closed, but not opened!")
			if Blocks.has(block):
				var value: String = Blocks[block]
				result += (value.replace("#inherited", blockcontent) if value.contains("#inherited") else value) + "\n"
			else:
				result += blockcontent
			block = ""
			blockcontent = ""
		elif block != "":
			blockcontent += line + "\n"
		else:
			result += line + "\n"
	return result


## TShader.LoadShader: the blocks of BlockFiles (texts, in the mesh's custom shader order) merged, applied to the base.
static func Compose(BaseString: String, BlockFiles: Array) -> String:
	var blocks := {}
	for i in range(BlockFiles.size() - 1, -1, -1):
		if BlockFiles[i] == "":
			continue
		var parsed := ParseBlocks(BlockFiles[i])
		for key in parsed:
			var value: String = parsed[key]
			if blocks.has(key):
				value = value.replace("#inherited", blocks[key])
			blocks[key] = value
	return ApplyBlocks(BaseString, blocks)


## The ported block file of an original shader name ('MatcapShader.fx', '\Graphics\Effects\Shader\Ice.fx'...);
## "" (and an error, the original fails to load the shader) when it is not ported.
static func LoadBlockFile(ShaderName: String) -> String:
	if ShaderName == "":
		return ""  # an effect without a shader (LoadShader skips empty block paths)
	var path := EFFECT_SHADER_ROOT + ShaderName.replace("\\", "/").get_file().get_basename().to_lower() + ".gdshaderinc"
	if _file_cache.has(path):
		return _file_cache[path]
	var text := ""
	if ResourceLoader.exists(path):
		text = (load(path) as ShaderInclude).code
	else:
		push_error("TShader: shader %s is not ported (%s)" % [ShaderName, path])
	_file_cache[path] = text
	return text


## The base template's text (standard_shader.gdshaderinc).
static func LoadBaseFile(path: String) -> String:
	if not _file_cache.has(path):
		_file_cache[path] = (load(path) as ShaderInclude).code
	return _file_cache[path]

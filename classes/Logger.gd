class_name Debug

static var _start_time: int = Time.get_ticks_msec()

static func _log(level: String, level_formatter: String, caller, args: Array):
	var elapsed: String = "%.2fs" % ((Time.get_ticks_msec() - _start_time) / 1000.0)
	var time_padding: String = " ".repeat(7 - elapsed.length())
	var referer: String
	if caller is String:
		referer = caller
	elif caller.get_script():
		referer = caller.get_script().get_path()
	else:
		referer = caller.get_class()
	
	print_rich(" ".join([
		"[color=#7F8C8D][b]%s%s[/b][/color]" % [elapsed, time_padding],       # Timestamp
		level_formatter % level.rpad(8),                                      # Level
		"[color=#9B59B6]%s[/color]" % ("/" + referer).split("/")[-1].rpad(18) # Caller
	]), " ".join(args))

static func info(caller, ...args):
	_log("INFO", "[color=#3DAEE9][b]%s[/b][/color]", caller, args)

static func debug(caller, ...args):
	_log("DEBUG", "[color=#3DAEE9][b]%s[/b][/color]", caller, args)

static func warn(caller, ...args):
	push_warning(" ".join(args))
	_log("WARNING", "[color=#FDBC4B][b]%s[/b][/color]", caller, args)

static func error(caller, ...args):
	push_error(" ".join(args))
	_log("ERROR", "[color=#ED1515]%s[/color]", caller, args)

static func critical(caller, ...args):
	assert(false, " ".join(args))
	_log("CRITICAL", "[bgcolor=#ED1515][color=#ffffff]%s[/color][/bgcolor]", caller, args)

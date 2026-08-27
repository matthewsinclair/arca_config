# P3b -- AF-01 executed correctly: pre-existing file pins resolution, then write fails
scratch = Path.dirname(__ENV__.file)
dir_b = Path.join(scratch, "probe_b2_ro")
File.rm_rf!(dir_b)
File.mkdir_p!(dir_b)
file_b = Path.join(dir_b, "ro.json")
File.write!(file_b, ~s({"existing": true}))

Application.put_env(:arca_config, :config_domain, :arca_config)
System.put_env("ARCA_CONFIG_CONFIG_PATH", dir_b)
System.put_env("ARCA_CONFIG_CONFIG_FILE", "ro.json")

say = fn tag, val -> IO.puts("#{tag}: #{inspect(val)}") end

say.("P3b.resolved_config_file", Arca.Config.Cfg.config_file())
{load_tag, _} = Arca.Config.Server.load_config()
say.("P3b.load", load_tag)

File.chmod!(file_b, 0o444)
File.chmod!(dir_b, 0o555)

say.("P3b.put_on_readonly_BUG_if_ok", Arca.Config.put("k", "v"))

File.chmod!(dir_b, 0o755)
File.chmod!(file_b, 0o644)
say.("P3b.disk_content_after", File.read!(file_b))
say.("P3b.get_k_after_failed_write_BUG_if_ok", Arca.Config.get("k"))
IO.puts("P3B_DONE")

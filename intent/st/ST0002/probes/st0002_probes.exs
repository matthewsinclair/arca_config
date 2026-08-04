# ST0002 Fable audit -- execution probes
# Run: mix run <this file> (from the arca_config repo root)
# Prints PROBE: RESULT lines; each line is evidence cited in design.md.

scratch = Path.dirname(__ENV__.file)
dir_a = Path.join(scratch, "probe_a")
dir_b = Path.join(scratch, "probe_b_ro")
File.rm_rf!(dir_a)
File.rm_rf!(dir_b)
File.mkdir_p!(dir_a)

say = fn tag, val -> IO.puts("#{tag}: #{inspect(val)}") end

# ---- P1: config_domain detection with no explicit domain set ----
Application.delete_env(:arca_config, :config_domain)
detected = Arca.Config.Cfg.config_domain()
say.("P1.detected_domain_without_explicit_config", detected)

say.(
  "P1.started_apps_head",
  Application.started_applications() |> Enum.map(&elem(&1, 0)) |> Enum.take(8)
)

Application.put_env(:arca_config, :config_domain, :arca_config)

# ---- point at dir A via app-specific env vars (domain :arca_config) ----
System.put_env("ARCA_CONFIG_CONFIG_PATH", dir_a)
System.put_env("ARCA_CONFIG_CONFIG_FILE", "probe.json")
File.write!(Path.join(dir_a, "probe.json"), ~s({"db": {"host": "old", "port": 1}}))
{load_tag, _} = Arca.Config.Server.load_config()
say.("load_config", load_tag)

# ---- P2: ancestor cache staleness after nested put ----
say.("P2.get_db_before", Arca.Config.get("db"))
say.("P2.put_db_host", Arca.Config.put("db.host", "new"))
say.("P2.get_db_host_after", Arca.Config.get("db.host"))
say.("P2.get_db_after_BUG_if_host_old", Arca.Config.get("db"))

say.(
  "P2.disk_db",
  File.read!(Path.join(dir_a, "probe.json")) |> Jason.decode!() |> Map.get("db")
)

# ---- P5: notification matrix (per-key subscriber, 1-arity, 0-arity) ----
me = self()
Arca.Config.subscribe("db.host")
Arca.Config.register_change_callback(:probe_cb1, fn _cfg -> send(me, :cb1_fired) end)
{:ok, _ref} = Arca.Config.add_callback(fn -> send(me, :cb0_fired) end)

flush = fn flush, acc ->
  receive do
    m -> flush.(flush, [m | acc])
  after
    700 -> Enum.reverse(acc)
  end
end

Arca.Config.put("db.host", "x2")
say.("P5.after_put_expect_configupdated_and_cb0_but_NO_cb1", flush.(flush, []))

Arca.Config.reload()
say.("P5.after_reload_expect_only_cb0", flush.(flush, []))

# The FileWatcher's external-change sequence is reload() then notify_external_change()
Arca.Config.Server.reload()
Arca.Config.Server.notify_external_change()
say.("P5.after_watcher_sequence_expect_cb1_once_cb0_TWICE_no_perkey", flush.(flush, []))

# ---- P7: env override underscore collapse ----
System.put_env("ARCA_CONFIG_CONFIG_OVERRIDE_LLM_CLIENT_TYPE", "echo")
say.("P7.load_config_phase", Arca.Config.load_config_phase())
say.("P7.get_dotted_llm.client.type_expect_ok", Arca.Config.get("llm.client.type"))
say.("P7.get_underscored_llm_client_type_expect_error", Arca.Config.get("llm_client_type"))
System.delete_env("ARCA_CONFIG_CONFIG_OVERRIDE_LLM_CLIENT_TYPE")

# ---- P3: truthful returns when the location is unwritable ----
File.mkdir_p!(dir_b)
File.chmod!(dir_b, 0o500)
System.put_env("ARCA_CONFIG_CONFIG_PATH", dir_b)
System.put_env("ARCA_CONFIG_CONFIG_FILE", "ro.json")
say.("P3.put_on_readonly_BUG_if_ok", Arca.Config.put("k", "v"))
say.("P3.file_written?", File.exists?(Path.join(dir_b, "ro.json")))
say.("P3.get_k_after_failed_write_BUG_if_ok", Arca.Config.get("k"))
File.chmod!(dir_b, 0o755)

IO.puts("PROBES_DONE")

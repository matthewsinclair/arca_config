# ST0002 execution probe output (verbatim)

Run context: 2026-08-04, HEAD 9925115, `mix run` from repo root, Elixir 1.20.2 / OTP 29. Scripts alongside this file. Interpretation and finding attribution live in `../design.md` (Method section carries the P3 -> AF-25 / P3b -> AF-01 attribution correction).

## Run 1 -- st0002_probes.exs

```
P1.detected_domain_without_explicit_config: :elixir_uuid
P1.started_apps_head: [:arca_config, :elixir_uuid, :table_rex, :pathex, :owl, :ucwidth, :certifi, :jason]
load_config: :ok
P2.get_db_before: {:ok, %{"host" => "old", "port" => 1}}
P2.put_db_host: {:ok, "new"}
P2.get_db_host_after: {:ok, "new"}
P2.get_db_after_BUG_if_host_old: {:ok, %{"host" => "old", "port" => 1}}
P2.disk_db: %{"host" => "new", "port" => 1}
P5.after_put_expect_configupdated_and_cb0_but_NO_cb1: [:cb0_fired, {:config_updated, ["db", "host"], "x2"}]
P5.after_reload_expect_only_cb0: [:cb0_fired]
P5.after_watcher_sequence_expect_cb1_once_cb0_TWICE_no_perkey: [:cb0_fired, :cb1_fired, :cb0_fired]
P7.load_config_phase: :ok
P7.get_dotted_llm.client.type_expect_ok: {:ok, "echo"}
P7.get_underscored_llm_client_type_expect_error: {:error, "Key not found"}
P3.put_on_readonly_BUG_if_ok: {:ok, "v"}
P3.file_written?: false
P3.get_k_after_failed_write_BUG_if_ok: {:ok, "v"}
PROBES_DONE
```

Post-run observation: `.arca_config/ro.json` appeared untracked in the repo root -- P3's write was redirected there by the `config_file/0` existence-flip (AF-25). The file was removed after capture; the 4 previously-committed `.arca_config/` artifacts were left for WP-05.

## Run 2 -- st0002_probe_p3b.exs (AF-01 executed with resolution pinned)

```
P3b.resolved_config_file: ".../scratchpad/probe_b2_ro/ro.json"
P3b.load: :ok
17:21:12.105 [error] Failed to write config file: :eacces
P3b.put_on_readonly_BUG_if_ok: {:ok, "v"}
P3b.disk_content_after: "{\"existing\": true}"
P3b.get_k_after_failed_write_BUG_if_ok: {:ok, "v"}
P3B_DONE
```

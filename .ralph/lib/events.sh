#!/usr/bin/env bash
# 两种 TUI 共用 provider 事件映射。sticky 输出带类型的单行记录，
# 保留文字片段边界；details 输出完整、可滚动的人话记录。
ralph_filter_events() {
  jq -Rr --arg mode "${1:?expected sticky or details}" --argjson reply_limit "${2:-131072}" \
    --arg fallback_clock "${3:-历史}" '
      def printable: . >= 32 and (. < 127 or . > 159);
      def safe: tostring | if test("[\u0000-\u0008\u000b-\u001f\u007f-\u009f]") then
          explode | map(select(. == 9 or . == 10 or printable)) | implode else . end;
      def compact($n):
        tostring as $s | ($s[:$n]) as $prefix |
        if ($prefix | test("\\p{Cc}|[^\\S ]|  ") | not) then $prefix else
          # 按需拆成小段，避免对整份工具输出逐码点展开或反复从开头切片。
          def chunks:
            if length <= 1024 then . else (length/2 | floor) as $mid | (.[:$mid], .[$mid:]) | chunks end;
          [limit($n;
            foreach ($s | chunks |
              gsub("[\u0000-\u0008\u000e-\u001f\u007f-\u0084\u0086-\u009f]+";"") |
              gsub("\\s{2,}|[^\\S ]";" ") | explode[]) as $c
              ({space:false}; {space:($c == 32), emit:($c != 32 or (.space|not))};
               if .emit then $c else empty end))] | implode
        end;
      def trunc($n): if $mode == "details" then safe else compact($n) end;
      # 只取事件本身含时区的时间戳。先换算成 UTC 秒，再按事件当天的本地时区显示。
      def event_clock:
        .timestamp | strings | select(length <= 64) |
        capture("\\A(?<wall>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:[.,][0-9]+)?(?:Z|(?<sign>[+-])(?<hh>[01][0-9]|2[0-3])(?::?(?<mm>[0-5][0-9]))?)\\z"; "i") |
        (.wall | ascii_upcase + "Z") as $utc |
        # 系统 mktime 也可能对合法的 epoch -1 报错，用回转比对区分它与非法日期。
        (try ($utc | fromdateiso8601) catch -1) as $epoch |
        select(($epoch | todateiso8601) == $utc) |
        (((.hh // "0" | tonumber) * 60 + (.mm // "0" | tonumber)) * 60) as $offset |
        (if .sign == "-" then $epoch + $offset else $epoch - $offset end) | strflocaltime("%H:%M:%S");
      def agy_error: (.result.error // .error // null);
      def agy_has_error:
        agy_error as $e |
        if $e == null then false
        elif ($e | type) == "string" or ($e | type) == "object" then ($e | length) > 0
        else false end;
      def agy_error_text:
        agy_error as $e |
        if ($e | type) == "object" then
          if (($e.message // "") | length) > 0 then ($e.message | tostring)
          elif (($e.type // "") | length) > 0 then "error type: " + ($e.type | tostring)
          else ($e | tostring) end
        elif ($e | type) == "string" then $e
        else "provider result status ERROR" end;
      def reply($op; $id; $text):
        {op: $op, id: (if $id[-1] == null then null else $id end), text: $text};
      def render:
      if .type == "system" and .subtype == "init" then
        "  ⚙ session " + ((.session_id // "") | .[0:8])
      elif .type == "assistant" then
        . as $event | ((.message.content // []) | if type == "array" then . else [] end) as $blocks |
        (if $mode == "sticky" then
           ([$blocks[] | select(.type == "text") | .text // empty] | join(" ")) as $text |
           if ($text | length) > 0 then reply("set"; ["claude", $event.message.id // $event.uuid]; $text) else empty end
         else empty end),
        ($blocks[] | if .type == "thinking" then "  💭 " + ((.thinking // "") | trunc(120))
            elif .type == "text" then (if $mode == "sticky" then empty else "  💬 " + ((.text // "") | trunc(120)) end)
            elif .type == "tool_use" then "  🔧 " + (.name // "?") + " " + ((.input // {}) | trunc(80))
            else empty end)
      elif .type == "user" then
        ((.message.content // []) | if type == "array" then . else [] end | .[]
          | select(.type == "tool_result")
          | (if .is_error then "  ❌ error: " else "  ⏎ result " end) + ((.content // "") | trunc(80)))
      elif .type == "result" then
        if .is_error then "  ❌ error: " + ((.result // .text // "") | trunc(120))
        elif $mode == "sticky" and ((.result // .text) | type) == "string" then
          reply("final"; ["result"]; .result // .text), "  ✓ result"
        elif has("text") then "  ✓ result " + ((.text // "") | trunc(120))
        elif .result != null then "  ✓ result " + ((.result // "") | trunc(120))
        elif .stats != null then
          "  ✓ result tokens=" + ((.stats.total_tokens // 0) | tostring)
          + " tools=" + ((.stats.tool_calls // 0) | tostring)
          + " dur=" + (((.stats.duration_ms // 0) / 1000 | floor) | tostring) + "s"
        else "  ✓ result" end
      elif .type == "thread.started" then
        "  ⚙ session " + ((.thread_id // "") | .[0:12])
      elif .type == "item.completed" and (.item.type // "") == "agent_message" then
        reply("set"; ["codex", .item.id]; .item.text // "")
      elif .type == "item.completed" and (.item.type // "") == "reasoning" then
        "  💭 " + ((.item.text // "") | trunc(120))
      elif .type == "item.started" and (.item.type // "") == "command_execution" then
        "  🔧 " + ((.item.command // "?") | trunc(80))
      elif .type == "item.completed" and (.item.type // "") == "command_execution" then
        (if .item.status == "failed" or .item.status == "declined" or ((.item.exit_code // 0) != 0)
          then "  ❌ command" else "  ⏎ command" end)
        + " exit=" + ((.item.exit_code // "unknown") | tostring)
        + " " + ((.item.aggregated_output // .item.output // .item.stdout // "") | trunc(80))
      elif .type == "item.completed" and (.item.type // "") == "file_change" then
        (if .item.status == "failed" then "  ❌ files " else "  ✓ files " end)
        + ((.item.changes // []) | trunc(120))
      elif (.type == "item.started" or .type == "item.completed") and (.item.type // "") == "mcp_tool_call" then
        (if .item.status == "failed" or .item.error != null then "  ❌ MCP "
          elif .type == "item.started" then "  🔧 MCP " else "  ⏎ MCP " end)
        + (.item.server // "?") + "/" + (.item.tool // "?") + " "
        + ((if .type == "item.started" then .item.arguments else .item.error // .item.result end) | trunc(120))
      elif .type == "item.completed" and (.item.type // "") == "web_search" then
        "  🔎 " + ((.item.query // "") | trunc(120))
      elif .type == "item.completed" and (.item.type // "") == "error" then
        "  ❌ error: " + ((.item.message // "") | trunc(120))
      elif .type == "turn.completed" then
        "  ✓ result"
      elif .type == "turn.failed" then
        "  ❌ error: " + ((.error.message // .message // "") | trunc(120))
      elif .type == "init" then
        "  ⚙ session " + ((.session_id // "") | .[0:12])
      elif .type == "message" and (.role // "") == "assistant" then
        reply("set"; ["message", .id]; .content // .text // "")
      elif .type == "tool_use" then
        "  🔧 " + ((.tool_name // .name // "?") | trunc(40)) + " " + (((.parameters // .input // {}) | tostring) | trunc(60))
      elif .type == "tool_result" then
        "  ⏎ result " + ((.output // .content // "") | tostring | trunc(80))
      elif .type == "text" then
        reply("set"; ["text", .id]; .text // "")
      elif .type == "complete" then
        if $mode == "sticky" and ((.text // "") | length) > 0 then
          reply("final"; ["complete"]; .text), "  ✓ result"
        else "  ✓ result " + ((.text // "") | trunc(120)) end
      elif .type == "error" then
        "  ❌ error: " + ((.error.message // .message // "") | trunc(120))
      elif .event == "init" then
        "  ⚙ session " + ((.conversation_id // .init.conversation_id // "") | .[0:12])
      elif .event == "step_update" then
        (.step_update // .) as $s |
        ($s.agent_response // .agent_response // {}) as $a |
        ($a.thinking_delta // $s.thinking_delta // $a.thinking // $s.thinking // "") as $thinking |
        ($a.text_delta // $s.text_delta // "") as $text |
        ($s.tool_name // "") as $tool |
        ($s.tool_info // {}) as $info |
        (($s.state // "") | tostring | ascii_upcase) as $state |
        (if ($thinking | length) > 0 then "  💭 " + ($thinking | trunc(120)) else empty end),
        (if ($text | length) > 0 then
          ($s.step_index | if type == "number" and . >= 0 and . <= 2147483647 and . == floor then . else null end) as $step |
          reply((if $step == null then "set" else "append" end);
            ["agy", $s.conversation_id // .conversation_id, $step]; $text)
         else empty end),
        (if ($tool | length) > 0 then
          if $state == "ERROR" or $state == "FAILED" or ($info | agy_has_error) then
            "  ❌ 失败 " + $tool + " → " + (($info.error // $info.output // "未提供错误详情") | trunc(120)) +
            (if $info.error != null and $info.output != null then " → 输出：" + ($info.output | trunc(120)) else "" end)
          elif $state == "DONE" then
            "  ✓ 完成 " + $tool +
            (if $info.output != null then " → " + ($info.output | trunc(120)) else "" end)
          else
            "  🔧 " + (if $state == "ACTIVE" or $state == "RUNNING" then "开始 "
              elif $state != "" then "[" + $state + "] " else "" end) + $tool + " " +
            (($info.command // $info.parameters // $info) | trunc(80))
          end
        elif $s.subagent_info != null then "  ⚙ subagent " + ($s.subagent_info | trunc(80))
        elif $mode == "details" and $s.step_type == "agent_response" and ($text | length) == 0 and ($thinking | length) == 0 then
          "  ⚙ agent_response " + $state
        else empty end)
      elif .event == "result" then
        ((.result.response // .response // "") as $response |
          if ($response | length) > 0 then
            if $mode == "sticky" then reply("final"; ["agy-result"]; $response)
            else "  💬 最终回复：" + ($response | trunc(120)) end
          else empty end),
        (if ((((.result.denied_actions // .denied_actions // []) | length)) > 0) then "  ❌ denied tools: " + (((.result.denied_actions // .denied_actions) | tostring) | trunc(100))
        elif agy_has_error then "  ❌ error: " + (agy_error_text | trunc(120))
        elif ((.result.status // .status // "") == "SUCCESS") then "  ✓ result"
        elif ((.result.status // .status // "") == "ERROR") then "  ❌ error: provider result status ERROR"
        else "  ⚠ unknown result status: " + ((.result.status // .status // "missing") | tostring | trunc(80)) end)
      elif $mode == "details" then "[provider event] " + (. | safe)
      else empty end;
      . as $raw |
      if startswith("{") then
        try (fromjson |
          (if $mode == "sticky" then (event_clock? // $fallback_clock) else null end) as $clock |
          render |
          if type == "object" then
            if $mode == "sticky" then .op + "\t" + $clock + "\t" +
              (if .op == "append" then (.id[1] | tojson) + "/" + (.id[2] | tostring)
               else (.id | tojson) end) + "\t" + (.text | compact($reply_limit))
            else "  💬 " + (.text | trunc(120)) end
          elif $mode == "sticky" then "event\t" + $clock + "\t" + compact(512)
          else safe end)
        catch (if $mode == "details" then "[provider unparsed] " + ($raw | safe) else empty end)
      elif $mode == "sticky" and test("^[0-9]+$") then "cursor\t-\t" + .
      elif $mode == "details" then "[provider] " + safe
      else empty end
  '
}

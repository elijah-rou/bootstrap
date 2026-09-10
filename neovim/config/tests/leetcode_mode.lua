vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local failures = {}
local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  if not condition then
    failures[#failures + 1] = message
  end
end

local function check_equal(actual, expected, message)
  check(actual == expected, ("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
end

local function check_error(callback, pattern, message)
  local ok, err = pcall(callback)
  check(not ok, message .. ": expected an error")
  if not ok then
    check(tostring(err):match(pattern) ~= nil, message .. ": unexpected error: " .. tostring(err))
  end
end

local original_mode = vim.env.NVIM_LEETCODE_MODE
local leetcode = require("config.leetcode")

vim.env.NVIM_LEETCODE_MODE = nil
check(not leetcode.enabled(), "an unset mode is disabled")
vim.env.NVIM_LEETCODE_MODE = "0"
check(not leetcode.enabled(), "zero mode is disabled")
vim.env.NVIM_LEETCODE_MODE = "1"
check(leetcode.enabled(), "one mode is enabled")
vim.env.NVIM_LEETCODE_MODE = "yes"
check_error(leetcode.enabled, "NVIM_LEETCODE_MODE", "ambiguous mode values are rejected")

local restart_count = 0
local function register_test_command(restart_available)
  leetcode.register_command({
    restart = function()
      restart_count = restart_count + 1
    end,
    restart_available = restart_available,
  })
end

register_test_command(false)
vim.env.NVIM_LEETCODE_MODE = nil
check_error(function()
  vim.cmd("LeetcodeMode on")
end, "requires Neovim 0%.12", "an unavailable restart command is rejected clearly")
check_equal(vim.env.NVIM_LEETCODE_MODE, nil, "an unavailable restart preserves the environment")
check_equal(restart_count, 0, "an unavailable restart is not called")

register_test_command(true)
check_error(function()
  vim.cmd("LeetcodeMode")
end, "on.*off.*toggle", "missing command argument is rejected")
check_error(function()
  vim.cmd("LeetcodeMode maybe")
end, "on.*off.*toggle", "unknown command argument is rejected")
check_equal(restart_count, 0, "invalid arguments do not restart")

vim.env.NVIM_LEETCODE_MODE = nil
vim.cmd("LeetcodeMode on")
check_equal(vim.env.NVIM_LEETCODE_MODE, "1", "on enables the mode")
check_equal(restart_count, 1, "on restarts")

vim.cmd("LeetcodeMode toggle")
check_equal(vim.env.NVIM_LEETCODE_MODE, nil, "toggle disables an enabled mode")
check_equal(restart_count, 2, "toggle restarts from enabled mode")

vim.cmd("LeetcodeMode toggle")
check_equal(vim.env.NVIM_LEETCODE_MODE, "1", "toggle enables a disabled mode")
check_equal(restart_count, 3, "toggle restarts from disabled mode")

vim.cmd("LeetcodeMode off")
check_equal(vim.env.NVIM_LEETCODE_MODE, nil, "off unsets the mode")
check_equal(restart_count, 4, "off restarts")

local dirty_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(dirty_buffer)
vim.api.nvim_buf_set_lines(dirty_buffer, 0, -1, false, { "unsaved" })
vim.bo[dirty_buffer].modified = true
vim.env.NVIM_LEETCODE_MODE = nil
check_error(function()
  vim.cmd("LeetcodeMode on")
end, "modified buffer", "modified buffers prevent mode changes")
check_equal(vim.env.NVIM_LEETCODE_MODE, nil, "a refused change preserves the environment")
check_equal(restart_count, 4, "a refused change does not restart")
vim.bo[dirty_buffer].modified = false
vim.api.nvim_buf_delete(dirty_buffer, { force = false })

local question_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(question_buffer, "/tmp/two-sum.go")
vim.api.nvim_buf_set_lines(question_buffer, 0, -1, false, { "package main", "func twoSum() {}" })
vim.bo[question_buffer].filetype = "go"
vim.api.nvim_set_current_buf(question_buffer)

local question_requests = {}
local question_presentations = {}
local question_answers = {
  "What invariant could help you avoid checking every pair?",
  "A slice is a descriptor over an array with a pointer, length, and capacity.",
  "Use make to allocate a map.",
}
leetcode.register_question_command({
  run_question = function(request, done)
    question_requests[#question_requests + 1] = request
    done(nil, question_answers[#question_requests])
  end,
  present_answer = function(question, answer)
    question_presentations[#question_presentations + 1] = { question = question, answer = answer }
  end,
  input = function(_, done)
    done("How do I allocate a Go map?")
  end,
})
check_equal(vim.fn.exists(":Question"), 2, "the interviewer command is registered")
vim.cmd("Question Which algorithm should I use?")
check_equal(#question_requests, 1, "an explicit question starts one request")
check_equal(question_requests[1].model, "openai-codex/gpt-5.6-sol", "Question uses GPT-5.6 Sol")
check_equal(question_requests[1].thinking, "medium", "Question uses medium thinking")
check_equal(question_requests[1].timeout_seconds, 120, "Question bounds request runtime")
check_equal(question_requests[1].kill_grace_seconds, 5, "Question bounds termination grace")
check(question_requests[1].system_prompt:match("technical interviewer") ~= nil, "the model acts as an interviewer")
check(
  question_requests[1].system_prompt:match("problem%-agnostic") ~= nil,
  "general language questions may be answered"
)
check(question_requests[1].system_prompt:match("never provide") ~= nil, "exercise solutions are withheld")
check(question_requests[1].prompt:match("two%-sum%.go") ~= nil, "the request includes the current buffer name")
check(question_requests[1].prompt:match("func twoSum%(%) {%}") ~= nil, "the request includes current buffer contents")
check(question_requests[1].prompt:match("Which algorithm should I use%?") ~= nil, "the request includes the question")
check_equal(question_presentations[1].answer, question_answers[1], "the first answer is presented")

vim.cmd("Question What is a Go slice?")
check_equal(#question_requests, 2, "a follow-up starts another request")
check(question_requests[2].prompt:match("Which algorithm should I use%?") ~= nil, "follow-ups include prior questions")
check(question_requests[2].prompt:match(question_answers[1], 1, true) ~= nil, "follow-ups include prior answers")

vim.cmd("Question")
check_equal(#question_requests, 3, "a missing argument opens the question input")
check(question_requests[3].prompt:match("How do I allocate a Go map%?") ~= nil, "input questions are submitted")

local fake_pi_directory = vim.fn.tempname()
local fake_pi_args = fake_pi_directory .. "/args"
local fake_pi_stdin = fake_pi_directory .. "/stdin"
vim.fn.mkdir(fake_pi_directory, "p")
vim.fn.writefile({
  "#!/bin/sh",
  'printf \'%s\\n\' "$@" > "$NVIM_QUESTION_TEST_ARGS"',
  'cat > "$NVIM_QUESTION_TEST_STDIN"',
  'case "$NVIM_QUESTION_TEST_MODE" in',
  "  overflow) head -c 70000 /dev/zero | tr '\\000' x ;;",
  "  error) printf 'synthetic failure\\n' >&2; exit 7 ;;",
  "  timeout) trap '' TERM; while :; do :; done ;;",
  "  *) printf 'Use the language documentation.\\n' ;;",
  "esac",
}, fake_pi_directory .. "/pi")
assert(vim.uv.fs_chmod(fake_pi_directory .. "/pi", 493))
local original_path = vim.env.PATH
vim.env.PATH = fake_pi_directory .. ":" .. original_path
vim.env.NVIM_QUESTION_TEST_ARGS = fake_pi_args
vim.env.NVIM_QUESTION_TEST_STDIN = fake_pi_stdin
local default_runner_answer
local original_system = vim.system
local runner_command
local runner_timeout
vim.system = function(command, options, done)
  runner_command = command
  runner_timeout = options.timeout
  return original_system(command, options, done)
end
leetcode.register_question_command({
  present_answer = function(_, answer)
    default_runner_answer = answer
  end,
})
vim.cmd("Question What does make do in Go?")
check(
  vim.wait(10000, function()
    return default_runner_answer ~= nil
  end, 10),
  "the default runner completes"
)
check_equal(default_runner_answer, "Use the language documentation.", "the default runner captures stdout")
check_equal(runner_command[1], "pi", "the runner does not require a platform-specific timeout executable")
check_equal(runner_timeout, 120000, "the runner uses Neovim's portable process timeout")
vim.system = original_system
local default_args = vim.fn.readfile(fake_pi_args)
local function has_argument(argument)
  return vim.tbl_contains(default_args, argument)
end
check(has_argument("openai-codex/gpt-5.6-sol"), "the default runner selects GPT-5.6 Sol")
check(has_argument("medium"), "the default runner selects medium thinking")
check(has_argument("--no-tools"), "the default runner disables tools")
check(has_argument("--no-extensions"), "the default runner disables extensions")
check(has_argument("--no-skills"), "the default runner disables skills")
check(has_argument("--no-prompt-templates"), "the default runner disables prompt templates")
check(has_argument("--no-themes"), "the default runner disables themes")
check(has_argument("--no-context-files"), "the default runner disables context files")
check(has_argument("--no-session"), "the default runner disables session persistence")
check(has_argument("--append-system-prompt"), "the default runner suppresses discovered appended prompts")
local default_stdin = table.concat(vim.fn.readfile(fake_pi_stdin), "\n")
check(default_stdin:match("What does make do in Go%?") ~= nil, "the default runner sends the question on stdin")
check(default_stdin:match("func twoSum%(%) {%}") ~= nil, "the default runner sends the current buffer on stdin")

local original_notify = vim.notify
local notification
vim.notify = function(message)
  notification = message
end
vim.env.NVIM_QUESTION_TEST_MODE = "overflow"
leetcode.register_question_command({ present_answer = function() end })
vim.cmd("Question Produce too much output")
check(
  vim.wait(10000, function()
    return notification ~= nil
  end, 10),
  "overflow errors complete"
)
check(notification:match("output exceeded") ~= nil, "overflow is rejected")

notification = nil
vim.env.NVIM_QUESTION_TEST_MODE = "error"
vim.cmd("Question Produce an error")
check(
  vim.wait(10000, function()
    return notification ~= nil
  end, 10),
  "stderr errors complete"
)
check(notification:match("synthetic failure") ~= nil, "stderr is reported")

local original_defer = vim.defer_fn
vim.system = function(command, options, done)
  options.timeout = 50
  return original_system(command, options, done)
end
vim.defer_fn = function(callback, milliseconds)
  check_equal(milliseconds, 125000, "the hard deadline includes termination grace")
  return original_defer(callback, 100)
end
notification = nil
vim.env.NVIM_QUESTION_TEST_MODE = "timeout"
vim.cmd("Question Exercise timeout")
check(
  vim.wait(2000, function()
    return notification ~= nil
  end, 10),
  "a process ignoring TERM is forcefully terminated"
)
check(tostring(notification):match("timed out") ~= nil, "the timeout is reported")
vim.system = original_system
vim.defer_fn = original_defer
local function interviewer_exit_handlers()
  return vim.tbl_filter(function(handler)
    return handler.desc == "Stop Leetcode interviewer on exit"
  end, vim.api.nvim_get_autocmds({ event = "VimLeavePre" }))
end
check_equal(#interviewer_exit_handlers(), 0, "completed requests release exit handlers")
notification = nil
vim.cmd("Question Exercise editor shutdown")
check_equal(#interviewer_exit_handlers(), 1, "running requests register editor-exit cleanup")
vim.api.nvim_exec_autocmds("VimLeavePre", {})
check(
  vim.wait(2000, function()
    return notification ~= nil
  end, 10),
  "editor exit kills the pending interviewer process"
)
check_equal(#interviewer_exit_handlers(), 0, "editor-exit cleanup leaves no stale handler")
vim.notify = original_notify
vim.env.NVIM_QUESTION_TEST_MODE = nil
vim.env.PATH = original_path
vim.env.NVIM_QUESTION_TEST_ARGS = nil
vim.env.NVIM_QUESTION_TEST_STDIN = nil
vim.fn.delete(fake_pi_directory, "rf")

local oversized_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(oversized_buffer, 0, -1, false, { string.rep("x", 131073) })
vim.api.nvim_set_current_buf(oversized_buffer)
local oversized_requests = 0
leetcode.register_question_command({
  run_question = function()
    oversized_requests = oversized_requests + 1
  end,
  present_answer = function() end,
})
check_error(function()
  vim.cmd("Question Can you read this?")
end, "buffer is too large", "oversized source buffers are rejected before spawning pi")
check_equal(oversized_requests, 0, "oversized source buffers do not start a request")
vim.api.nvim_buf_delete(oversized_buffer, { force = true })
vim.api.nvim_set_current_buf(question_buffer)

leetcode.register_question_command({
  run_question = function(_, done)
    done(nil, "Start by naming the invariant.")
  end,
})
vim.cmd("Question Give me a hint")
local answer_buffer = vim.fn.bufnr("leetcode-question://interviewer")
check(answer_buffer >= 0, "the default presenter creates an interviewer buffer")
check_equal(vim.api.nvim_get_current_buf(), question_buffer, "the default presenter preserves source-buffer focus")
check(
  table.concat(vim.api.nvim_buf_get_lines(answer_buffer, 0, -1, false), "\n"):match("Start by naming the invariant%.")
    ~= nil,
  "the default presenter displays the answer"
)
local original_answer_window = vim.fn.win_findbuf(answer_buffer)[1]
local replacement_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(original_answer_window, replacement_buffer)
leetcode.register_question_command({
  run_question = function(_, done)
    done(nil, "Consider the complement you need.")
  end,
})
vim.cmd("Question Another hint")
check_equal(
  vim.api.nvim_win_get_buf(original_answer_window),
  replacement_buffer,
  "the presenter does not overwrite a repurposed window"
)
check(#vim.fn.win_findbuf(answer_buffer) > 0, "the presenter recreates a visible answer window")
vim.api.nvim_buf_delete(replacement_buffer, { force = true })
vim.api.nvim_buf_delete(answer_buffer, { force = true })

local duplicate_presentations = 0
leetcode.register_question_command({
  run_question = function(_, done)
    done(nil, "first")
    done(nil, "second")
  end,
  present_answer = function()
    duplicate_presentations = duplicate_presentations + 1
  end,
})
vim.cmd("Question Complete once")
check_equal(duplicate_presentations, 1, "duplicate process completions are ignored")

local pending_question
leetcode.register_question_command({
  run_question = function(_, done)
    pending_question = done
  end,
  present_answer = function() end,
})
vim.cmd("Question First")
check_error(function()
  vim.cmd("Question Second")
end, "already in progress", "concurrent interviewer requests are rejected")
pending_question(nil, "Continue by stating the invariant.")
vim.api.nvim_buf_delete(question_buffer, { force = true })

if vim.env.NVIM_BUNDLED_RUNTIME == "1" then
  local repository = vim.fn.getcwd()
  local temporary_directory = vim.fn.tempname()
  local isolated_data_directory = temporary_directory .. "/data"
  local isolated_config_directory = temporary_directory .. "/config"
  vim.fn.mkdir(isolated_config_directory .. "/nvim", "p")
  vim.fn.writefile({ '{"version":1,"profile":"bare"}' }, isolated_config_directory .. "/nvim/bootstrap-profile.json")
  local isolated_nvim_data = isolated_data_directory .. "/nvim"
  local treesitter_runtime = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
  local language_cases = {
    { name = "Go", filetype = "go", extension = "go", source = { "package main", "", "func main() {}" } },
    { name = "Rust", filetype = "rust", extension = "rs", source = { "fn main() {}" } },
    { name = "Zig", filetype = "zig", extension = "zig", source = { "pub fn main() void {}" } },
  }
  check(vim.uv.fs_stat(treesitter_runtime) ~= nil, "the configured Tree-sitter runtime is installed")
  vim.fn.mkdir(isolated_nvim_data .. "/lazy", "p")
  vim.fn.mkdir(isolated_nvim_data .. "/site/parser", "p")
  assert(vim.uv.fs_symlink(treesitter_runtime, isolated_nvim_data .. "/lazy/nvim-treesitter", { dir = true }))
  for _, language in ipairs(language_cases) do
    local parser = vim.api.nvim_get_runtime_file("parser/" .. language.filetype .. ".so", false)[1]
    check(type(parser) == "string" and parser ~= "", language.name .. " Tree-sitter parser is installed")
    assert(vim.uv.fs_symlink(parser, isolated_nvim_data .. "/site/parser/" .. language.filetype .. ".so"))
    language.source_path = temporary_directory .. "/solution." .. language.extension
    vim.fn.writefile(language.source, language.source_path)
  end
  vim.fn.mkdir(temporary_directory .. "/plugin", "p")
  vim.fn.writefile(
    { "vim.g.leetcode_test_startup_plugin_loaded = true" },
    temporary_directory .. "/plugin/leetcode_test.lua"
  )

  local probe_path = temporary_directory .. "/probe.lua"
  vim.fn.writefile({
    "local state = {",
    '  command_available = vim.fn.exists(":LeetcodeMode") == 2,',
    '  question_available = vim.fn.exists(":Question") == 2,',
    "  completefunc = vim.bo.completefunc,",
    "  ctrl_n_mapping = vim.fn.maparg([[<C-n>]], [[i]]),",
    "  ctrl_p_mapping = vim.fn.maparg([[<C-p>]], [[i]]),",
    "  data_directory = vim.fn.stdpath([[data]]),",
    "  filetype = vim.bo.filetype,",
    "  foldexpr = vim.wo.foldexpr,",
    "  foldlevel = vim.wo.foldlevel,",
    "  foldmethod = vim.wo.foldmethod,",
    "  lazy_stub_loaded = vim.g.leetcode_test_lazy_stub_loaded == true,",
    "  loadplugins = vim.o.loadplugins,",
    "  lsp_clients = #vim.lsp.get_clients({ bufnr = 0 }),",
    "  number = vim.o.number,",
    "  source_path = vim.api.nvim_buf_get_name(0),",
    "  startup_plugin_loaded = vim.g.leetcode_test_startup_plugin_loaded == true,",
    "  syntax = vim.bo.syntax,",
    "  treesitter_active = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil,",
    "}",
    "vim.fn.writefile({ vim.json.encode(state) }, vim.env.NVIM_LEETCODE_TEST_OUTPUT)",
  }, probe_path)

  local function startup_probe(mode, language)
    local output_path = temporary_directory .. "/result-" .. mode .. "-" .. language.filetype .. ".json"
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--cmd",
        "set runtimepath^=" .. vim.fn.fnameescape(repository),
        "--cmd",
        "set runtimepath^=" .. vim.fn.fnameescape(temporary_directory),
        "--cmd",
        "lua package.preload['config.lazy'] = function() vim.g.leetcode_test_lazy_stub_loaded = true; return {} end",
        "-u",
        repository .. "/init.lua",
        "-c",
        "luafile " .. vim.fn.fnameescape(probe_path),
        "-c",
        "qa!",
        language.source_path,
      }, {
        env = {
          NVIM_LEETCODE_MODE = mode,
          NVIM_LEETCODE_TEST_OUTPUT = output_path,
          XDG_DATA_HOME = isolated_data_directory,
          XDG_CONFIG_HOME = isolated_config_directory,
        },
        text = true,
      })
      :wait(10000)

    check_equal(result.code, 0, "startup exits successfully in mode " .. mode)
    local output = vim.fn.readfile(output_path)
    check_equal(#output, 1, "startup writes one probe result in mode " .. mode)
    if #output ~= 1 then
      return {}
    end
    return vim.json.decode(output[1])
  end

  for _, language in ipairs(language_cases) do
    local minimal = startup_probe("1", language)
    local prefix = language.name .. " minimal startup "
    check_equal(minimal.command_available, true, prefix .. "registers LeetcodeMode")
    check_equal(minimal.question_available, true, prefix .. "registers Question")
    check_equal(minimal.loadplugins, false, prefix .. "disables plugin loading")
    check_equal(minimal.startup_plugin_loaded, false, prefix .. "skips startup plugins")
    check_equal(minimal.lazy_stub_loaded, false, prefix .. "skips config.lazy")
    check_equal(minimal.number, true, prefix .. "applies editor setup")
    check_equal(minimal.source_path, language.source_path, prefix .. "opens the source-file argument")
    check_equal(minimal.filetype, language.filetype, prefix .. "detects the source filetype")
    check_equal(minimal.syntax, "", prefix .. "replaces regex syntax when Tree-sitter starts")
    check_equal(minimal.treesitter_active, true, prefix .. "enables Tree-sitter highlighting")
    check_equal(minimal.foldmethod, "expr", prefix .. "enables expression folding")
    check_equal(minimal.foldexpr, "v:lua.vim.treesitter.foldexpr()", prefix .. "uses Tree-sitter folding")
    check_equal(minimal.foldlevel, 99, prefix .. "opens folds by default")
    check_equal(minimal.lsp_clients, 0, prefix .. "does not attach LSP clients")
    check_equal(minimal.completefunc, "", prefix .. "preserves native manual completion")
    check_equal(minimal.ctrl_n_mapping, "", prefix .. "leaves native next completion unmapped")
    check_equal(minimal.ctrl_p_mapping, "", prefix .. "leaves native previous completion unmapped")
    check_equal(minimal.data_directory, isolated_nvim_data, prefix .. "uses isolated data")
  end

  local normal = startup_probe("0", language_cases[1])
  check_equal(normal.command_available, true, "normal startup registers LeetcodeMode")
  check_equal(normal.question_available, false, "normal startup does not register the interview Question command")
  check_equal(normal.lazy_stub_loaded, true, "normal startup takes the config.lazy path")
  check_equal(normal.data_directory, isolated_nvim_data, "normal startup uses isolated data")
  check_equal(vim.fn.isdirectory(isolated_nvim_data .. "/lazy/lazy.nvim"), 0, "startup probes do not install lazy.nvim")

  vim.fn.delete(temporary_directory, "rf")
else
  print("SKIP installed Tree-sitter startup probes; set NVIM_BUNDLED_RUNTIME=1 to include them")
end
vim.env.NVIM_LEETCODE_MODE = original_mode

if #failures > 0 then
  error(("%d/%d assertions failed:\n- %s"):format(#failures, assertions, table.concat(failures, "\n- ")))
end

print(("ok: %d assertions"):format(assertions))

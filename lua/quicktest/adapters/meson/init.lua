local Job = require("plenary.job")
local util = require("quicktest.adapters.meson.util")
local meson = require("quicktest.adapters.meson.meson")
local test_parser = require("quicktest.adapters.meson.test_parser")

local M = {
  name = "meson test runner for C assuming Criterion test frame work",
}

local parsed_test_output = {}

---@class Test
---@field test_suite string
---@field test_name string

---@class MesonTestParams
---@field test Test
---@field test_exe string
---@field bufnr integer
---@field cursor_pos integer[]

---@param bufnr integer
---@param cursor_pos integer[]
---@return MesonTestParams
M.build_file_run_params = function(bufnr, cursor_pos)
  local test_exe = util.get_test_exe_from_buffer(bufnr)

  if test_exe == nil then
    return {}
  end

  return {
    test = {},
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return MesonTestParams
M.build_line_run_params = function(bufnr, cursor_pos)
  local test_exe = util.get_test_exe_from_buffer(bufnr)
  local line = test_parser.get_nearest_test(bufnr, cursor_pos)

  if line == nil or test_exe == nil then
    return {}
  end

  local test = test_parser.get_test_suite_and_name(line)
  return {
    test = test,
    test_exe = test_exe,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
  }
end

--- Determines if the test can be run with the given parameters.
--- Attempt to run if params is not an empty table
---@param params MesonTestParams
---@return boolean
M.can_run = function(params)
  return next(params) ~= nil
end

--- Executes the test with the given parameters.
---@param params MesonTestParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  -- It is not necessary to compile before running the tests as meson does this automatically.
  -- However, we explicitly call meson compile here to capture the build output so that
  -- we can show potential build errors in the UI.
  -- Otherwise the test will fail silently-ish providing little insight to the user.
  local compile = meson.compile()
  if compile.return_val ~= 0 then
    for _, line in ipairs(compile.text) do
      send({ type = "stderr", output = line })
    end
    send({ type = "exit", code = compile.return_val })
    return -1
  end

  --- Run the tests
  local job = Job:new({
    command = "meson",
    args = util.make_test_args(params.test_exe, params.test.test_suite, params.test.test_name),
    on_stdout = function(_, data)
      data = util.capture_json(data, parsed_test_output)
      if data then
        util.print_results(parsed_test_output.text, send)
      end
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()
  return job.pid -- Return the process ID
end

--- Handles actions to take after the test run, based on the results.
---@param params MesonTestParams
---@param results any
M.after_run = function(params, results)
  -- Implement actions based on the results, such as updating UI or handling errors
  -- print(vim.inspect(params.data))
  if parsed_test_output.text == nil then
    return
  end
  -- print(xml_output.text)
  -- print(vim.inspect(parsed_data))
  -- print(parsed_data["id"])
  -- print(parsed_data["test_suites"][1]["name"])
end

--- Checks if the plugin is enabled for the given buffer.
---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = util.get_filename(bufname)
  return vim.startswith(filename, "test_") and vim.endswith(filename, ".c")
end

---@param params MesonTestParams
---@return string
M.title = function(params)
  if params.test.test_suite ~= nil and params.test.test_name ~= nil then
    return "Testing " .. params.test.test_suite .. "/" .. params.test.test_name
  else
    return "Running tests from " .. params.test_exe
  end
end

return M

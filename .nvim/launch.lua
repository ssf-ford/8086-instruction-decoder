local dap = require 'dap'

dap.configurations.zig = {
  {
    name = 'Launch (Auto-build)',
    type = 'codelldb',
    request = 'launch',
    program = '${workspaceFolder}/zig-out/bin/decode',
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = { 'assignment_2/listing_0039_more_mov_operations' },
    -- prelaunchTask = "zig build",
    preLaunchTask = function()
      -- Try multiple build command variations for maximum compatibility
      local build_commands = {
        { 'zig', 'build' }, -- Default (Debug mode)
        { 'zig', 'build', '--release=safe' }, -- Current preferred syntax
        { 'zig', 'build', '-Doptimize=Debug' }, -- Alternative current syntax
        { 'zig', 'build', '-ODebug' }, -- Direct compiler flag
        { 'zig', 'build', '-Drelease-safe=false' }, -- Legacy fallback
      }
      -- For debugging, we want Debug mode, so try in order of preference
      for _, cmd in ipairs(build_commands) do
        local handle = vim.system(cmd, {
          cwd = vim.fn.getcwd(),
          text = true,
        })
        local result = handle:wait()
        if result.code == 0 then
          vim.notify('Build successful with: ' .. table.concat(cmd, ' '), vim.log.levels.INFO)
          return true
        end
      end
      vim.notify('All build attempts failed!', vim.log.levels.ERROR)
      return false
    end,
  },
}

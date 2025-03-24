-- lua/issue_from_comment/init.lua
local M = {}

-- Configuration variables
M.config = {
  github_token = os.getenv("GITHUB_TOKEN"), -- Get from environment or set in init.lua
  github_owner = nil,                       -- Set this in your config
  github_repo = nil,                        -- Set this in your config
  default_labels = {},                      -- Default labels for issues
  default_assignees = {},                   -- Default assignees for issues
  create_key = '<Leader>gc',                -- Key to create the issue from buffer
  cancel_key = 'q',                         -- Key to cancel and close the buffer
}

-- Set up the plugin with user config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register the command
  vim.api.nvim_create_user_command("GHIssueFromComment", function()
    M.create_issue_from_comment()
  end, {})
end

-- Main function
function M.create_issue_from_comment()
  -- Get the current line
  local line = vim.api.nvim_get_current_line()

  -- Extract comment text without comment markers
  local comment_text = nil

  -- Match different comment styles
  comment_text = line:match("^%s*//+%s*(.+)$")  -- C-style comments
  if not comment_text then
    comment_text = line:match("^%s*#+%s*(.+)$") -- Hash comments
  end
  if not comment_text then
    comment_text = line:match("^%s*%-%-+%s*(.+)$") -- Dash comments
  end

  if not comment_text then
    vim.notify("No comment found on the current line", vim.log.levels.ERROR)
    return
  end

  -- If the comment has a colon, only take text after the colon
  local post_colon = comment_text:match(":(.+)$")
  if post_colon then
    comment_text = post_colon
  end

  -- Trim whitespace
  comment_text = vim.trim(comment_text)

  -- Debug info
  vim.notify("Extracted title: " .. comment_text, vim.log.levels.INFO)

  -- Open the issue creation buffer with the cleaned text
  M.open_issue_buffer(comment_text, line)
end

-- Open a new buffer for editing issue details
function M.open_issue_buffer(title, original_line)
  -- Create a new buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "GitHub Issue")

  -- Prepare default labels
  local default_labels = ""
  if M.config.default_labels and #M.config.default_labels > 0 then
    default_labels = table.concat(M.config.default_labels, ", ")
  end

  -- Prepare default assignees
  local default_assignees = ""
  if M.config.default_assignees and #M.config.default_assignees > 0 then
    default_assignees = table.concat(M.config.default_assignees, ", ")
  end

  -- Get the configuration for the create and cancel keys
  local create_key = M.config.create_key or '<Leader>gc'
  local cancel_key = M.config.cancel_key or 'q'

  -- Set buffer content
  local lines = {
    "# GitHub Issue Creation",
    "",
    "## Title",
    title or "<!-- Enter issue title here -->",
    "",
    "## Description",
    "<!-- Enter issue description here -->",
    "",
    "## Labels (comma-separated)",
    default_labels or "<!-- e.g. bug, enhancement -->",
    "",
    "## Assignees (comma-separated)",
    default_assignees or "<!-- e.g. username1, username2 -->",
    "",
    string.format("<!-- Press %s to create the issue or %s to cancel -->", create_key, cancel_key)
  }

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set buffer local mappings
  vim.api.nvim_buf_set_keymap(bufnr, 'n', create_key,
    string.format(":lua require('issue_from_comment').submit_issue(%d, %d)<CR>",
      bufnr, vim.api.nvim_get_current_buf()),
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', cancel_key,
    string.format(":lua vim.api.nvim_buf_delete(%d, {force = true})<CR>", bufnr),
    { noremap = true, silent = true })

  -- Store original info
  vim.api.nvim_buf_set_var(bufnr, "original_line", original_line)
  vim.api.nvim_buf_set_var(bufnr, "original_bufnr", vim.api.nvim_get_current_buf())
  vim.api.nvim_buf_set_var(bufnr, "original_line_nr", vim.api.nvim_win_get_cursor(0)[1] - 1)

  -- Open the buffer in a split
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, bufnr)

  -- Set buffer options
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false

  -- Put cursor in title section
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
end

-- Create GitHub issue via API
function M.create_github_issue(title, description, labels, assignees, issue_bufnr)
  -- Check if curl is available
  vim.fn.jobstart("which curl", {
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("curl is not available. Please install curl.", vim.log.levels.ERROR)
        return
      end

      -- Check if token is available
      if not M.config.github_token or M.config.github_token == "" then
        vim.notify("GitHub token is not set. Please set it via GITHUB_TOKEN environment variable or in your config.",
          vim.log.levels.ERROR)
        return
      end

      -- Check if owner and repo are set
      if not M.config.github_owner or not M.config.github_repo then
        vim.notify("GitHub owner or repo is not set. Please configure them in your setup.", vim.log.levels.ERROR)
        return
      end

      -- Prepare payload
      local payload = vim.fn.json_encode({
        title = title,
        body = description,
        labels = labels,
        assignees = assignees
      })

      -- GitHub API endpoint
      local url = string.format("https://api.github.com/repos/%s/%s/issues",
        M.config.github_owner, M.config.github_repo)

      -- Notify user about the request (for debugging)
      vim.notify(string.format("Creating issue in %s/%s...", M.config.github_owner, M.config.github_repo))

      -- Make the API call using curl
      local cmd = string.format(
        'curl -s -X POST -H "Authorization: Bearer %s" -H "Content-Type: application/json" -d \'%s\' %s',
        M.config.github_token,
        payload:gsub("'", "'\\''"), -- Escape single quotes for shell
        url
      )

      vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
          if data and #data > 1 then
            local response = table.concat(data, "\n")
            local success, json = pcall(vim.fn.json_decode, response)

            if success and json.number then
              -- Update original comment with issue number
              M.update_original_comment(issue_bufnr, json.number)
              vim.notify(string.format("Issue #%d created successfully!", json.number), vim.log.levels.INFO)
              -- Close the issue buffer on success
              vim.api.nvim_buf_delete(issue_bufnr, { force = true })
            else
              vim.notify("Failed to parse GitHub response: " .. response, vim.log.levels.ERROR)
            end
          end
        end,
        on_stderr = function(_, data)
          if data and #data > 1 then
            vim.notify("GitHub API error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
          end
        end,
        on_exit = function(_, code)
          if code ~= 0 then
            vim.notify("Failed to create GitHub issue. Exit code: " .. code, vim.log.levels.ERROR)
          end
        end
      })
    end
  })
end

-- Submit the issue to GitHub
function M.submit_issue(issue_bufnr, original_bufnr)
  -- Get the buffer contents
  local lines = vim.api.nvim_buf_get_lines(issue_bufnr, 0, -1, false)

  -- Parse the buffer to extract information
  local title = ""
  local description = ""
  local labels = {}
  local assignees = {}

  local current_section = nil

  for _, line in ipairs(lines) do
    if line:match("^## Title") then
      current_section = "title"
    elseif line:match("^## Description") then
      current_section = "description"
    elseif line:match("^## Labels") then
      current_section = "labels"
    elseif line:match("^## Assignees") then
      current_section = "assignees"
    elseif line:match("^%-%-") or line:match("^#") or line:match("^<!%-%-") then
      -- Skip instruction lines, headers, and HTML comments
    elseif current_section == "title" and line ~= "" then
      title = line
    elseif current_section == "description" and line ~= "" then
      description = description .. line .. "\n"
    elseif current_section == "labels" and line ~= "" then
      for label in line:gmatch("([^,]+)") do
        local trimmed = vim.trim(label)
        if trimmed ~= "" then
          table.insert(labels, trimmed)
        end
      end
    elseif current_section == "assignees" and line ~= "" then
      for assignee in line:gmatch("([^,]+)") do
        local trimmed = vim.trim(assignee)
        if trimmed ~= "" and not trimmed:match("^%-%-") then
          table.insert(assignees, trimmed)
        end
      end
    end
  end

  -- Validate fields
  if title == "" then
    vim.notify("Issue title cannot be empty", vim.log.levels.ERROR)
    return
  end

  -- Make API call to GitHub
  M.create_github_issue(title, description, labels, assignees, issue_bufnr)
end

-- Update the original comment with the issue number
function M.update_original_comment(issue_bufnr, issue_number)
  local original_bufnr = vim.api.nvim_buf_get_var(issue_bufnr, "original_bufnr")
  local line_nr = vim.api.nvim_buf_get_var(issue_bufnr, "original_line_nr")
  local line = vim.api.nvim_buf_get_lines(original_bufnr, line_nr, line_nr + 1, false)[1]

  -- Append issue number to the end of the comment
  local updated_line = line .. " #" .. issue_number
  vim.api.nvim_buf_set_lines(original_bufnr, line_nr, line_nr + 1, false, { updated_line })
end

return M

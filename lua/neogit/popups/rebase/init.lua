-- https://magit.vc/manual/2.11.0/magit/Rebasing.html#Rebasing
local cli = require("neogit.lib.git.cli")
local branch = require("neogit.lib.git.branch")
local git = require("neogit.lib.git")
local popup = require("neogit.lib.popup")
local rebase = require("neogit.lib.git.rebase")
local input = require("neogit.lib.input")

local CommitSelectViewBuffer = require("neogit.buffers.commit_select_view")
local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

local M = {}
local a = require("plenary.async")

local function in_rebase()
  return git.repo.rebase.head
end

-- TODO: When rebasing, pressing <cr> on a commit should open it in commit view
function M.create()
  local status = require("neogit.status")
  local p = popup.builder():name("NeogitRebasePopup")
  local base_branch = git.config.get("neogit.baseBranch").value or "master"

  if not in_rebase() then
    p:switch("k", "keep-empty", "Keep empty commits")
      :switch("u", "update-refs", "Update branches")
      :switch("d", "committer-date-is-author-date", "Use author date as committer date")
      :switch("t", "ignore-date", "Use current time as author date")
      :switch("a", "autosquash", "Autosquash fixup and squash commits")
      :switch("A", "autostash", "Autostash", { enabled = true })
      :switch("i", "interactive", "Interactive")
      :switch("h", "no-verify", "Disable hooks")
      :option("s", "gpg-sign", "", "Sign using gpg")
      :option("r", "rebase-merges", "", "Rebase merges")
      :group_heading("Rebase " .. (branch.current() and (branch.current() .. " ") or "") .. "onto")
      :action_if(branch.current() ~= base_branch, "p", base_branch, function(popup)
        rebase.rebase_onto(base_branch, popup:get_arguments())
        a.util.scheduler()
        status.refresh(true, "rebase_master")
      end)
      :action(
        "u",
        git.repo.upstream.ref, -- use upstream ((If there is no upstream, add ", setting that" suffix))
        function(popup)
          rebase.rebase_onto(git.repo.upstream.remote .. " " .. git.repo.upstream.branch, popup:get_arguments())
          a.util.scheduler()
          status.refresh(true, "rebase_upstream")
        end
      )
      :action("e", "elsewhere", function(popup)
        local elsewhere = FuzzyFinderBuffer.new(git.branch.get_all_branches()):open_sync()

        rebase.rebase_onto(elsewhere, popup:get_arguments())
        a.util.scheduler()
        status.refresh(true, "rebase_elsewhere")
      end)
      :new_action_group("Rebase")
      :action("i", "interactively", function(popup)
        local commits = require("neogit.lib.git.log").list()
        local commit = CommitSelectViewBuffer.new(commits):open_async()
        if not commit then
          return
        end

        rebase.rebase_interactive(commit, unpack(popup:get_arguments()))
        a.util.scheduler()
        status.refresh(true, "rebase_interactive")
      end)
      :action("s", "a subset", false)
      :new_action_group()
      :action("m", "to modify a commit", false)
      :action("w", "to reword a commit", false)
      :action("k", "to remove a commit", false)
      :action("f", "to autosquash", false)
  else
    p:group_heading("Actions")
      :action("r", "Continue", function()
        rebase.continue()
        a.util.scheduler()
        status.refresh(true, "rebase_continue")
      end)
      :action("s", "Skip", function()
        rebase.skip()
        a.util.scheduler()
        status.refresh(true, "rebase_skip")
      end)
      :action("e", "Edit", false)
      :action("a", "Abort", function()
        if not input.get_confirmation("Abort rebase?", { values = { "&Yes", "&No" }, default = 2 }) then
          return
        end

        cli.rebase.abort.call_sync():trim()
        a.util.scheduler()
        status.refresh(true, "rebase_abort")
      end)
  end

  p = p:build()
  p:show()

  return p
end

return M

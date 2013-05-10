
module GitFlow
  module Common

    def run(cmd)
      case GitFlow.verbose
      when 1
        puts "#{cmd}"
      when 2
        puts "[#{caller[0]}] #{cmd}"
      end
      result = `#{cmd}`.strip
      @success = $?.exitstatus.zero?
      if GitFlow.verbose > 1
        puts result unless result.empty?
        puts "[#{$?.exitstatus}]"
      end
      result
    end

    def run_successful(cmd)
      run(cmd)
      @success
    end

    def escape(s)
      s.gsub(/([\.\+\$\*])/, '\\\\\1')
      s.gsub(/\([\.\$\*]\)/, '\\\\\1')
    end

    def git_local_branches
      run("git branch --no-color").split("\n").collect do |b|
        b.sub(/^[* ] /, '')
      end
    end

    def git_remote_branches
      run("git branch -r --no-color").split("\n").collect do |b|
        b.sub(/^[* ] /, '')
      end
    end

    def git_all_branches
      git_local_branches + git_remote_branches
    end

    def git_all_tags
      run("git tag").split("\n")
    end

    def git_current_branch
      run("git branch --no-color").split("\n").each do |b|
        return b.sub(/^\* /, '') if b =~ /^\* / and b !~ /no branch/
      end
      nil
    end

    def git_is_clean_working_tree
      return 1 unless run_successful("git diff --no-ext-diff --ignore-submodules --quiet --exit-code")
      return 2 unless run_successful("git diff-index --cached --quiet --ignore-submodules HEAD --")
      return 0
    end

    def git_repo_is_headless
      !run_successful("git rev-parse --quiet --verify HEAD >/dev/null 2>&1")
    end

    def git_local_branch_exists(b)
      git_local_branches.include?(b)
    end

    def git_remote_branch_exists(b)
      git_remote_branches.include?(b)
    end

    def git_branch_exists(b)
      git_all_branches.include?(b)
    end

    def git_tag_exists(t)
      git_all_tags.include?(t)
    end

    # Tests whether branches and their "origin" counterparts have diverged and need
    # merging first. It returns error codes to provide more detail, like so:
    #
    # 0    Branch heads point to the same commit
    # 1    First given branch needs fast-forwarding
    # 2    Second given branch needs fast-forwarding
    # 3    Branch needs a real merge
    # 4    There is no merge base, i.e. the branches have no common ancestors
    def git_compare_branches(b1, b2)
      commit1 = run("git rev-parse #{b1}").strip
      commit2 = run("git rev-parse #{b2}").strip
      if commit1 != commit2
        base = run("git merge-base #{commit1} #{commit2}").strip
        return 4 unless @success
        return 1 if commit1 == base
        return 2 if commit2 == base
        return 3
      else
        return 0
      end
    end

    # Checks whether branch subject is succesfully merged into base
    def git_is_branch_merged_into(subject, base)
      all_merges = run("git branch --no-color --contains #{subject}").split("\n").collect do |b|
        b.sub(/^[* ] /, '')
      end
      all_merges.include?(base)
    end

    def get_git_config_item(item)
      value = run("git config --get #{item}").strip
      value = nil if value.empty?
      value
    end

    # check if this repo has been inited for gitflow
    def gitflow_has_master_configured
      master = get_git_config_item("gitflow.branch.master")
      master and git_local_branch_exists(master)
    end

    def gitflow_has_develop_configured
      develop = get_git_config_item("gitflow.branch.develop")
      develop and git_local_branch_exists(develop)
    end

    def gitflow_has_prefixes_configured
      get_git_config_item('gitflow.prefix.feature') and
        get_git_config_item('gitflow.prefix.release') and
        get_git_config_item('gitflow.prefix.hotfix') and
        get_git_config_item('gitflow.prefix.support') and
        (get_git_config_item('gitflow.prefix.versiontag') or @success)
    end

    def gitflow_is_initialized
      master = get_git_config_item('gitflow.branch.master')
      develop = get_git_config_item('gitflow.branch.develop')
      master and develop and master != develop and gitflow_has_prefixes_configured
    end

    # loading settings that can be overridden using git config
    def gitflow_load_settings
      @dot_git_dir = run('git rev-parse --git-dir 2>&1').strip
      @master_branch = run('git config --get gitflow.branch.master').strip
      @develop_branch = run('git config --get gitflow.branch.develop').strip
      @origin = get_git_config_item('gitflow.origin') || 'origin'
    end

    # Inputs:
    # name = name prefix to resolve
    # prefix = branch prefix to use
    #
    # Searches branch names from git_local_branches() to look for a unique
    # branch name whose name starts with the given name prefix.
    #
    # There are multiple exit codes possible:
    # The unambiguous full name of the branch is returned (success)
    # 1: No match is found.
    # 2: Multiple matches found. These matches are written to stderr
    def gitflow_resolve_nameprefix(name, prefix)
      # first, check if there is a perfect match
      return name if git_local_branch_exists("#{prefix}#{name}")

      matches = git_local_branches.find_all do |b|
        b =~ /^#{escape(prefix + name)}/
      end
      case matches.size
      when 0
        # no prefix match, so take it literally
        warn "No branch matches prefix '#{name}'"
        return 1
      when 1
        return matches[0]
      else
        # multiple matches, cannot decide
        warn "Multiple branches match prefix '#{name}':"
        matches.each do |match|
          warn "- #{match}"
        end
        return 2
      end
    end

    def gitflow_resolve_nameprefix(name, prefix)
      # first, check if there is a perfect match
      return name if git_local_branch_exists(prefix + name)

      matches = git_local_branches.find_all do |b|
        b =~ /^#{escape(prefix + name)}/
      end
      case matches.size
      when 0
        # no prefix match, so take it literally
        warn "No branch matches prefix '#{name}'"
        return 1
      when 1
        return matches[0]
      else
        # multiple matches, cannot decide
        warn "Multiple branches match prefix '#{name}':"
        matches.each do |match|
          warn "- #{match}"
        end
        return 2
      end
    end

    def require_git_repo
      abort "fatal: Not a git repository" unless run_successful('git rev-parse --git-dir >/dev/null 2>&1')
    end

    def require_gitflow_initialized
      abort "fatal: Not a gitflow-enabled repo yet. Please run \"git flow init\" first." unless gitflow_is_initialized
    end

    def require_clean_working_tree
      case git_is_clean_working_tree
      when 1
        abort "fatal: Working tree contains unstaged changes. Aborting."
      when 2
        abort "fatal: Index contains uncommited changes. Aborting."
      end
    end

    def require_local_branch(b)
      abort "fatal: Local branch '#{b}' does not exist and is required." unless git_local_branch_exists(b)
    end

    def require_remote_branch(b)
      abort "Remote branch '#{b}' does not exist and is required." unless git_remote_branches.include?(b)
    end

    def require_branch(b)
      abort "Branch '#{b}' does not exist and is required." unless git_all_branches.include?(b)
    end

    def require_branch_absent(b)
      abort "Branch '#{b}' already exists. Pick another name." if git_all_branches.include?(b)
    end

    def require_tag_absent(t)
      abort "Tag '#{t}' already exists. Pick another name." if git_all_tags.include?(t)
    end

    def require_branches_equal(b1, b2)
      require_local_branch(b1)
      require_remote_branch(b2)
      status = git_compare_branches(b1, b2)
      if status > 0
        warn "Branches '#{b1}' and '#{b2}' have diverged."
        if status == 1
          abort "And branch '#{b1}' may be fast-forwarded."
        elsif status  == 2
          # Warn here, since there is no harm in being ahead
          warn "And local branch '#{b1}' is ahead of '#{b2}'."
        else
          abort "Branches need merging first."
        end
      end
    end
  end
end

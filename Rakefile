
dir = File.expand_path("..", __FILE__)

desc "Rebuild the flattened repo from ../bosh project"
task :rebuild do
  sh "rm -rf .git"
  sh "rm -rf bosh*"

  patched_projects = %w[bosh_cli_plugin_micro bosh_vsphere_cpi bosh-registry]
  patched_projects.each do |proj|
    sh "cp -R ../bosh/#{proj} ."
  end

  bosh_sha=`cd ../bosh; git show HEAD --oneline | awk '{print $1}'`.strip
  bosh_branch=`cd ../bosh; git branch | grep '*' | awk '{print $2}'`.strip

  sh "git init"
  sh "git add ."
  sh "git commit -m 'Created from branch #{bosh_branch}, commit #{bosh_sha}'"

  sh "git remote add origin git@github.com:drnic/flattened_bosh_for_traveling_bosh.git"
  sh "git push origin master -f"
end

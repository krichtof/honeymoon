desc 'Publishing honeymoon on github'
task :deploy do
  puts 'Publishing honeymoon blog on github, silence is golden...'
  sh 'jekyll build'
  sh 'cd ../honeymoon'
  sh 'git add .'
  sh 'git commit -m "update"'
end
require 'rubygems'
require 'sinatra'
require 'yaml'
require 'json'
require File.expand_path(File.join(File.dirname(__FILE__), '/../shared/testbot'))
require File.expand_path(File.join(File.dirname(__FILE__), 'memory_model.rb'))
require File.expand_path(File.join(File.dirname(__FILE__), 'job.rb'))
require File.expand_path(File.join(File.dirname(__FILE__), 'group.rb'))
require File.expand_path(File.join(File.dirname(__FILE__), 'runner.rb'))
require File.expand_path(File.join(File.dirname(__FILE__), 'build.rb'))

module Testbot::Server

  if ENV['INTEGRATION_TEST']
    set :port, 22880
  else
    set :port, Testbot::SERVER_PORT
  end

  class Server
    def self.valid_version?(runner_version)
      Testbot.version == runner_version
    end

    def self.runner_attributes runner
      runner.attributes
        .merge(build: nil)
        .merge(status: status_for_runner(runner))
    end

    def self.status_for_runner runner
      Job.all.find_all { |job| job.taken_by == runner }.map { |job| job.status }.join("/")
    end
  end

  post '/builds' do
    if Runner.total_instances == 0
      [ 503, "No runners available" ]
    else
      Build.create_and_build_jobs(params).id.to_s
    end
  end

  get '/builds/:id' do
    Job.release_jobs_taken_by_missing_runners!
    build = Build.find(params[:id])
    build.destroy if build.done
    { "done" => build.done, "results" => build.results, "success" => build.success }.to_json
  end

  delete '/builds/:id' do
    build = Build.find(params[:id])
    build.destroy if build
    nil
  end

  get '/jobs/next' do
    job, runner = Job.next(params, @env['REMOTE_ADDR'])
    if job
      job.update(:taken_at => Time.now, :taken_by => runner)
      job.build.logln "job##{job.id} assigned to runner<#{runner.hostname}>. unassigned jobs:#{job.build.remaining_jobs.count}/#{job.build.all_jobs.count} done jobs:#{job.build.done_jobs.count}/#{job.build.all_jobs.count} "
      [ job.id, job.build.id, job.project, job.root, job.type, (job.jruby == 1 ? 'jruby' : 'ruby'), job.files ].join(',')
    end
  end

  put '/jobs/:id' do
    Job.find(params[:id]).update(:result => params[:result], :status => params[:status]); nil
  end

  get '/runners/ping' do
    return unless Server.valid_version?(params[:version])
    runner = Runner.find_by_uid(params[:uid])
    if runner
      runner.update(params.reject { |k, v| k == "build_id" }.merge({ :last_seen_at => Time.now, :build => Build.find(params[:build_id]) }))
      unless params[:build_id] == '' || params[:build_id] == nil || runner.build
        return "stop_build,#{params[:build_id]}"
      end
    end
    nil
  end

  get '/runners' do
    Runner.find_all_available.map { |r| Server.runner_attributes r }.to_json
  end

  get '/runners/outdated' do
    Runner.find_all_outdated.map { |runner| [ runner.ip, runner.hostname, runner.uid ].join(' ') }.join("\n").strip
  end

  get '/runners/available_instances' do
    Runner.available_instances.to_s
  end

  get '/runners/total_instances' do
    Runner.total_instances.to_s
  end

  get '/runners/available' do
    Runner.find_all_available.map { |runner| [ runner.ip, runner.hostname, runner.uid, runner.username, runner.idle_instances ].join(' ') }.join("\n").strip
  end

  get '/version' do
    Testbot.version
  end

  get '/status' do
    File.read(File.join(File.dirname(__FILE__), '/status/status.html'))
  end

  get '/status/:dir/:file' do
    content_type :js if params[:file] =~ /\.js$/

    File.read(File.join(File.dirname(__FILE__), "/status/#{params[:dir]}/#{params[:file]}"))
  end

end


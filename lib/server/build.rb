module Testbot::Server

  class Build < MemoryModel

    def initialize(hash)
      super({ :success => true, :done => false, :results => '' }.merge(hash))
    end

    def self.create_and_build_jobs(hash)
      hash["jruby"] = (hash["jruby"] == "true") ? 1 : 0
      build = create(hash.reject { |k, v| k == 'available_runner_usage' })
      build.create_jobs!(hash['available_runner_usage'])
      build
    end

    def create_jobs!(available_runner_usage)
      groups = Group.build(self.files.split, self.sizes.split.map { |size| size.to_i },
                           Runner.total_instances.to_f * (available_runner_usage.to_i / 100.0), self.type)
      groups.each do |group|
        Job.create(:files => group.join(' '),
                   :root => self.root,
                   :project => self.project,
                   :type => self.type,
                   :build => self,
                   :jruby => self.jruby)
      end
    end

    def all_jobs
      Job.all.find_all { |j| j.build == self }
    end

    def done_jobs
      Job.all.find_all { |j| j.done && j.build == self }
    end

    def remaining_jobs no_jruby=nil
      Job.remaining_jobs(self.id, no_jruby)
    end

    def destroy
      all_jobs.each { |job| job.destroy }
      super
    end

    def logln message
      log "\n" if self.results[-1] != "\n"
      log "#{message}\n"
    end

    def log message
      self.results += message
    end

  end

end

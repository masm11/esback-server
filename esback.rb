#!/usr/bin/env ruby

require 'securerandom'
require 'webrick'
require 'openssl'
require 'fileutils'

BASEDIR = '/home/backup/android'

@sess_to_dir = {}

def handle_begin(req, res)
  sess = SecureRandom.uuid
  dir = Time.now.localtime.strftime('%Y%m%d-%H%M%S')
  @sess_to_dir[sess] = dir
  res.cookies << WEBrick::Cookie.new('session', sess)
end

def handle_file(req, res)
  sess = req.cookies.select{|c| c.name == 'session'}.first.value
  dir = @sess_to_dir[sess]
  unless dir
    res.status = 403
    return
  end
  
  cachedir = "#{BASEDIR}/.esback_cache"
  unless File.exist? cachedir
    Dir.mkdir(cachedir)
    16.times do |hi|
      h = '%x' % hi
      16.times do |lo|
        l = '%x' % lo
        Dir.mkdir("#{cachedir}/#{h}#{l}")
      end
    end
  end
  
  dir = "#{BASEDIR}/#{dir}"
  Dir.mkdir(dir) unless File.exist? dir
  
  filepath = req.path.sub(%r|^/file/|, '').sub(%r|^/*|, '')
  filepath_sha256 = OpenSSL::Digest::SHA256.hexdigest(filepath)
  filepath_div = filepath_sha256.slice(0, 2)
  filepath = "#{dir}/#{filepath}"
  
  body = req.body
  body_sha256 = OpenSSL::Digest::SHA256.hexdigest(body)
  new_cachefile = "#{cachedir}/#{filepath_div}/#{filepath_sha256}-#{body_sha256}"
  
  old_cachefile = Dir.glob("#{cachedir}/*/*-#{body_sha256}").first
  
  unless File.exist? new_cachefile
    if old_cachefile
      File.link old_cachefile, new_cachefile unless old_cachefile == new_cachefile
    else
      File.write new_cachefile, body
    end
  end
  FileUtils.mkdir_p File.dirname(filepath)
  File.link new_cachefile, filepath
  
end

def handle_keep(req, res)
  sess = req.cookies.select{|c| c.name == 'session'}.first.value
  dir = @sess_to_dir[sess]
  unless dir
    res.status = 403
    return
  end
  
  cachedir = "#{BASEDIR}/.esback_cache"
  unless File.exist? cachedir
    Dir.mkdir(cachedir)
    16.times do |hi|
      h = '%x' % hi
      16.times do |lo|
        l = '%x' % lo
        Dir.mkdir("#{cachedir}/#{h}#{l}")
      end
    end
  end
  
  dir = "#{BASEDIR}/#{dir}"
  Dir.mkdir(dir) unless File.exist? dir
  
  if req.body
    req.body.split("\n").each do |filepath|
      filepath = filepath.sub(%r|^/*|, '')
      filepath_sha256 = OpenSSL::Digest::SHA256.hexdigest(filepath)
      filepath_div = filepath_sha256.slice(0, 2)
      filepath = "#{dir}/#{filepath}"
      
      new_cachefile = Dir.glob("#{cachedir}/#{filepath_div}/#{filepath_sha256}-*").first
      if new_cachefile
        FileUtils.mkdir_p File.dirname(filepath)
        File.link new_cachefile, filepath
      end
    end
  end
  
end

def handle_finish(req, res)
  sess = req.cookies.select{|c| c.name == 'session'}.first.value
  dir = @sess_to_dir[sess]
  unless dir
    res.status = 403
    return
  end
  puts dir
  @sess_to_dir[sess] = nil
end

srv = WEBrick::HTTPServer.new({
                                DocumentRoot: './',
                                BindAddress: '127.0.0.1',
                                Port: 8083,
                              })
srv.mount_proc '/begin' do |req, res|
  handle_begin(req, res)
end
srv.mount_proc '/file/' do |req, res|
  handle_file(req, res)
end
srv.mount_proc '/keep/' do |req, res|
  handle_keep(req, res)
end
srv.mount_proc '/finish' do |req, res|
  handle_finish(req, res)
end
srv.start

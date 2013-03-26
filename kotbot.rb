#!/usr/bin/env ruby
require "rubygems"
require "bundler/setup"

Bundler.require

require "dm-migrations"

puts "using db: #{File.expand_path File.dirname(__FILE__)}/kotbot.db"
DataMapper.setup(:default, "sqlite://#{File.expand_path File.dirname(__FILE__)}/kotbot.db")

class Memo
    include DataMapper::Resource
    property :id,         Serial
    property :target,     String
    property :text,       Text
    property :source,     String
    property :created_at, DateTime

    def Memo.for(user)
      Memo.all(target: user)
    end

    def to_s
      "#{created_at.strftime("%d.%m %H:%M")} <#{source}> #{target}: #{text}"
    end
end

class Nick
  include DataMapper::Resource
  belongs_to :alias

  property :id,         Serial
  property :nick,       String
end

class Alias
  include DataMapper::Resource
  has n, :nicks

  property :id,         Serial
  property :alias,      String

  def Alias.get_nicks_for(user_alias)
    alias_model = Alias.first(alias: user_alias)
    if alias_model.nil?
      [user_alias]
    else
      alias_model.nicks.all.map {|n| n.nick}
    end
  end

  def Alias.build(user_alias, nicks)
    alias_model = Alias.first(alias: user_alias)

    if alias_model.nil?
      alias_model = Alias.create(alias: user_alias)
      alias_model.save
    end

    alias_model.nicks.all.each do |nick|
      nick.destroy!
    end
    nicks.each do |nick|
      n = Nick.create(nick: nick)
      alias_model.nicks << n
      n.save
    end
  end
end

DataMapper.finalize
DataMapper.auto_upgrade!

bot = Cinch::Bot.new do
  configure do |c|
    c.server = "irc.freenode.org"
    c.channels = ["##kotik"]
    c.nick = "kotbot"
  end

  on :message do |m|
    user = m.user.nick.gsub(/_*$/,"")
    Memo.for(user).each do |memo|
      m.channel.send memo.to_s
      memo.destroy!
    end
  end
  on :message, /^!alias\s+(.+?)\s+(.+)/ do |m, new_alias, nicks|
    Alias.build(new_alias, nicks.split(/\s+/))
    m.reply "#{new_alias}: #{Alias.get_nicks_for(new_alias).join(", ")}"
  end

  on :message, /^!alias_show (.+?)\s*$/ do |m, query|
    m.reply Alias.get_nicks_for(query).join(", ")
  end

  on :message, /^!m (.+?) (.+)/ do |m, nick, message|
    real_nicks = Alias.get_nicks_for(nick).each do |real_nick|
      if real_nick == m.user.nick
        m.reply "You can't leave memos for yourself.."
      elsif real_nick == bot.nick
        m.reply "You can't leave memos for me.."
      else
        memo = Memo.create(target: real_nick, text: message, source: m.user.nick, created_at: Time.now)
        memo.save
      end
    end
    m.reply "Added memo for #{real_nicks.join(' ')}"
  end

  on :message, /^!help/ do |m|
    m.channel.send "uzycie: !m <user> <message>"
  end
end

bot.start

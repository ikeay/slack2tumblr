# Herokuに挙げる際にこれがないとエラー
require 'bundler'
Bundler.require

# Sinatraアプリを動かす
require './main.rb'
run Sinatra::Application
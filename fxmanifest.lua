fx_version 'cerulean'
game 'gta5'


dependencies { 'es_extended', 'oxmysql' }

shared_script 'config.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', 'server.lua' } 
client_script 'client.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

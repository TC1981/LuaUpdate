# LuaUpdate for OPNsense

Shell script to check WAN interface IP change and if the IP has been changed then update the DNS A record.

## Installation steps:
1. Add cron job to OPNsense GUI
    ```bash
    sudo cp actions_luaupdate.conf /usr/local/opnsense/service/conf/actions.d/
    ```
2. Add script to /usr/home
    ```bash
    sudo cp luaupdate.sh /usr/home
    ```
3. Set execution rights for others
    ```bash
    sudo chmod o+x /usr/home/luaupdate.sh
    ```
4. Restart configd
    ```bash
    sudo service configd restart
    ```
5. Test cron job
    ```bash
    sudo configctl luaupdate start
    ```
6. Add cronjob on UI (runs every 3 minutes)
    ```bash
    0/3	*	*	*	*
    ```
from fabric.api import run, env
from utils.tools import Tool
import logging

env.hosts = ['ubuntu@192.168.56.101', 'ubuntu@192.168.56.102', '172.17.17.154']

def test():
    nicId = 0
    tool = Tool()

    ping = tool.ping()

    vifs = tool.vif()
    adapter = tool.adapter()
    ping = tool.ping()
    nh = tool.nh()
    rt = tool.rt()



    try:
        vifs.cmd(add="Container NIC " + str(nicId), mac="00:00:00:00:01", type="virtual", vrf=1, vif=11)
        #run(vifs)

        #adapter.cmd(double_dash=False, SwitchName="veth", Name="00:00:00:00:01", ManagementOS="virtual")
        #adapter.execute(prefix="Add-VMNetworkAdapter")

        ping.cmd(double_dash=False, arg="8.8.8.8", c="5")
        #ping.execute()
        run(ping())
        run(ping())
        #nh.cmd(create=1, vrf="0", type=4)
        #nh.execute()

        #rt.cmd(double_dash=False, c="", v=1, f=1, e="ff:ff:ff:ff:ff:ff", n=1)
        #rt.execute()

        #vifs.cmd(add="pkt0", mac="00:00:5e:00:01:00", type="agent", vrf=1, vif=1)
        #vifs.execute()

    except Exception as e:
        logging.error(e)
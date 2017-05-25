import logging

from utils.tools import Tool

if __name__ == "__main__":
    nicId = 0
    tool = Tool()
    vifs = tool.vif()
    adapter = tool.adapter()
    ping = tool.ping()
    nh = tool.nh()
    rt = tool.rt()

    try:
        vifs.cmd(add="Container NIC " + str(nicId), mac="00:00:00:00:01", type="virtual", vrf=1, vif=11)
        vifs.execute()

        adapter.cmd(double_dash=False, SwitchName="veth", Name="00:00:00:00:01", ManagementOS="virtual")
        adapter.execute(prefix="Add-VMNetworkAdapter")

        ping.cmd(double_dash=False, arg="8.8.8.8", c="5")
        ping.execute()

        nh.cmd(create=1, vrf="0", type=4)
        nh.execute()

        rt.cmd(double_dash=False, c="", v=1, f=1, e="ff:ff:ff:ff:ff:ff", n=1)
        rt.execute()

        vifs.cmd(add="pkt0", mac="00:00:5e:00:01:00", type="agent", vrf=1, vif=1)
        vifs.execute()

    except Exception as e:
        logging.error(e)
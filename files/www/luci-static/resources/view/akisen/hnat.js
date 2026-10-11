'use strict';
'require view';
'require form';

return view.extend({
    render: function() {
        var m = new form.Map('akisen-hnat', 'MTK HNAT 硬件加速',
            '保留闭源驱动的 HNAT 模块，默认关闭。开启 OpenClash 或校园网 TTL/IPID 功能时，系统自动暂停 HNAT，以保证流量经过相应规则。关闭这些服务后，可恢复硬件加速。');
        var s = m.section(form.NamedSection, 'main', 'settings');
        s.addremove = false;
        var o = s.option(form.Flag, 'enabled', '允许直连硬件加速');
        o.default = '0';
        o.rmempty = false;
        return m.render();
    }
});

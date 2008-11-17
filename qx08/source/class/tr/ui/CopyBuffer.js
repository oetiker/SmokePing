/* ************************************************************************
   Copyright: 2008, OETIKER+PARTNER AG
   License: GPL
   Authors: Tobias Oetiker
   $Id: $
* ************************************************************************ */

/**
 * Place an instance of this widget into the application root. It will remain
 * invisible. I will listen on the 'copy' bus for data to get ready for copying with
 * [ctrl]+[c]
 */
qx.Class.define('tr.ui.CopyBuffer', {
    extend : qx.ui.form.TextArea,

    construct : function() {
        this.base(arguments);

        this.set({
            width      : 0,
            height     : 0,
            allowGrowX : false,
            allowGrowY : false,
            decorator  : null
        });

        qx.event.message.Bus.subscribe('copy', this.__copy, this);
    },

    members : {
        /**
         * TODOC
         *
         * @type member
         * @param m {var} TODOC
         * @return {void} 
         */
        __copy : function(m) {
            var data = m.getData();
            this.info('set: ' + data);
            this.setValue(data);
            this.selectAll();
        }
    }
});
/* ************************************************************************

   Tr Frontend

   Author:
     * Tobias Oetiker

************************************************************************ */
/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * A configurable cell renderre
 */

qx.Class.define('Tr.ui.Cellrenderer', 
{
    extend: qx.ui.table.cellrenderer.Number,
    /**
    * Format a number with a configurable number of fraction digits
    * and add optional pre and postfix.
    * @param digits {Integer} how many digits should there be. Default is 0.
    * @param prefix {String} optional prefix.
    * @param postfix {String} optional postfix.
    */

    construct: function (digits,postfix,prefix) {
        if (digits == undefined){
            digits = 0;
        }
        this.base(arguments)
        var format = new qx.util.format.NumberFormat();
        format.set({
            maximumFractionDigits: digits,
            minimumFractionDigits: digits
        });
        if (postfix != undefined){
            format.setPostfix(postfix);
        }
        if (prefix != undefined){
            format.setPrefix(prefix);
        }            
        this.setNumberFormat(format);
    }
});

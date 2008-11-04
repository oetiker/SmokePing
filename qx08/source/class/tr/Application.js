/* ************************************************************************

   Copyright: OETIKER+PARTNER AG

   License: Gnu GPL Verrsion 3

   Authors: Tobias Oetiker <tobi@oetiker.ch>

************************************************************************ */

/* ************************************************************************

#asset(tr/*)

************************************************************************ */

/**
 * This is the main application class of your custom application "qx08"
 */
qx.Class.define("tr.Application",
{
  extend : qx.application.Standalone,

  /*
  *****************************************************************************
     MEMBERS
  *****************************************************************************
  */

  members :
  {
    /**
     * This method contains the initial application code and gets called 
     * during startup of the application
     */
    main : function()
    {
      var self=this;
      // Call super class
      this.base(arguments);

      // Enable logging in debug variant
      if (qx.core.Variant.isSet("qx.debug", "on"))
      {
        // support native logging capabilities, e.g. Firebug for Firefox
        qx.log.appender.Native;
        // support additional cross-browser console. Press F7 to toggle visibility
        qx.log.appender.Console;
      }

      /*
      -------------------------------------------------------------------------
        Below is your actual application code...
      -------------------------------------------------------------------------
      */


      // if we run with a file:// url make sure 
      // the app finds the Tr service (Tr.cgi)
      Tr.Server.getInstance().setLocalUrl(
          'http://johan.oetiker.ch/~oetiker/tr/'
      );
      var root=this.getRoot();
      // Document is the application root
      var root = new qx.ui.container.Composite(new qx.ui.layout.VBox());
      this.getRoot().add(root, { left : 0, top: 0});

   

      var top = new qx.ui.container.Composite(new qx.ui.layout.HBox());
      var title = new qx.ui.basic.Atom('SmokeTrace 2.4.2');
      with(title){
           setTextColor('#b0b0b0');
           setFont(qx.bom.Font.fromString('20px bold sans-serif'));
      }
      top.add(title);
      top.add(new qx.ui.basic.HorizontalSpacer());
      top.add(new Tr.ui.ActionButton());
      root.add(top);
      var trace = new Tr.ui.TraceTable();
      root.add(trace);
      root.add(new Tr.ui.Footer(this.tr("SmokeTrace is part of the of the SmokePing suite created by Tobi Oetiker, Copyright 2008."),'http://oss.oetiker.ch/smokeping')); 
  }
});

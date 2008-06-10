/* ************************************************************************

#module(Tr)
#resource(Tr.image:image)
#embed(Tr.image/*)

************************************************************************ */

qx.Class.define('Tr.Application', 
{
    extend: qx.application.Gui,
       
    members: 
    {           
        main: function()
        {
            var self=this;
            this.base(arguments);

	        qx.io.Alias.getInstance().add(
    	       'MT', qx.core.Setting.get('Tr.resourceUri')
        	);

  			// if we run with a file:// url make sure 
			// the app finds the Tr service (Tr.cgi)

            Tr.Server.getInstance().setLocalUrl(
			    'http://johan.oetiker.ch/~oetiker/tr/'
            );

            var base_layout = new qx.ui.layout.VerticalBoxLayout();
            with(base_layout){
                setPadding(8);
                setLocation(0,0);
                setWidth('100%');
                setHeight('100%');
                setSpacing(2);
                setBackgroundColor('white');
            };            
            base_layout.addToDocument();
            var top = new qx.ui.layout.HorizontalBoxLayout();
            top.set({
                height: 'auto'
            });
			var title = new qx.ui.basic.Atom('SmokeTrace VERSION');
			with(title){
            	setTextColor('#b0b0b0');
            	setFont(qx.ui.core.Font.fromString('20px bold sans-serif'));
			}
			top.add(title);
            top.add(new qx.ui.basic.HorizontalSpacer());
            top.add(new Tr.ui.ActionButton());
            base_layout.add(top);
			var trace = new Tr.ui.TraceTable();
            base_layout.add(trace);
            base_layout.add(new Tr.ui.Footer(this.tr("SmokeTrace is part of the SmokePing suite created by Tobi Oetiker, Copyright 2008."),'http://oss.oetiker.ch/smokeping'));   
        },
            
        close : function(e)
        {
            this.base(arguments);
            // return "Tr Web UI: "
            //      + "Do you really want to close the application?";
        },
        
			
		terminate : function(e) {
			this.base(arguments);
		}

        /********************************************************************
         * Functional Block Methods
         ********************************************************************/

    },
		



    /*
    *****************************************************************************
    SETTINGS
    *****************************************************************************
    */

    settings : {
			'Tr.resourceUri' : './resource'
	}
});
 

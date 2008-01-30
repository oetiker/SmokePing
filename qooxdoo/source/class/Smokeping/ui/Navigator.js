/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * The widget showing a detail graph
 */

qx.Class.define('Smokeping.ui.Navigator',
{
    extend: qx.ui.window.Window,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param graph_url   {String}   Url to the explorable graph
     *
     */

    construct: function (graph) {
		this._graph = graph;
		with(this){
			base(arguments,tr("Smokeping Graph Navigator"));
			set({
				showMaximize: false,
				showMinimize: false,
				width:		  300,
				height:		  200,
				minWidth: 	  300,
				minHeight:    200,
				backgroundColor: '#f0f0f0'
			});
		}
		this._graph_width = 300;
		this._graph_height = 200;
		this._lastrun = 0;
		this._loader = new Smokeping.ui.LoadingAnimation();
		this._url = Smokeping.Server.getInstance().getUrl();
		this._update_image();
    },

	members: {
		// resizable objects have a changeWidth method
		// which we can override to take part in the fun
		// why I have to access this._graph_width without the this.
        // in this case
		_changeWidth: function(newWidth) {
			var diff = newWidth - this.getBoxWidth();			
			this.base(arguments, newWidth);
			this.add(this._loader);
			this._graph_width = this._graph_width + diff;
			qx.client.Timer.once(this._update_image,this,250);
		},

		_changeHeight: function(newHeight) {			
			var diff = newHeight - this.getBoxHeight();
			this.base(arguments, newHeight);
			this.add(this._loader);
			this._graph_height = this._graph_height + diff;
 			qx.client.Timer.once(this._update_image,this,250);

		},

		_get_url: function(){
                    return this._url+ '?g='+this._graph+';s=now-1d;e=now;t=100000;b=0;w='+this._graph_width+';h='+this._graph_height;
		},

		_update_image: function(){
			var now = (new Date()).getTime();
            if (this._lastrun + 1000 < now) {
				this._preloader = qx.io.image.PreloaderManager.getInstance().create(this._get_url())
              	if (this._preloader.isLoaded()){
     		        	qx.client.Timer.once(this._show_image,this,0);
	          	} else {
       	        	this._preloader.addEventListener('load', this._show_image, this);
           	  	}
  				this._lastrun = now;
			}
			else {
               	this.debug('Skipping update since previous update less tahn 1 second')
       	    }
		},

		_show_image: function(e){
			with(this){
				set({
					width: 'auto',
					height: 'auto'
				});
				var image = new qx.ui.basic.Image();
				image.setPreloader(this._preloader);
   				qx.io.image.PreloaderManager.getInstance().remove(this._preloader);
				removeAll();
				add(image);
                var zoomer = new Smokeping.ui.Zoomer(image,this._graph_width,this._graph_height,33,30);
                add(zoomer);
                var mover = new Smokeping.ui.Mover(image,this._url+ '?g='+this._graph,this._graph_width,this._graph_height,33,30,1201680005,1201686005);
                add(mover);
			}
		}
	}


});
 
 

/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * a widget showing the smokeping graph overview
 */

var  Smokeping_ui_Graph_default_width = null;
var  Smokeping_ui_Graph_default_height = null;

qx.Class.define('Smokeping.ui.Graph', 
{
    extend: qx.ui.layout.BoxLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param base_url   {String}   Path to the location of the image generator
     *
     */

    construct: function (src,width,height) {
		this.base(arguments);
		this._src=src;
		this._width=width;
		this._height=height;
		if ( Smokeping_ui_Graph_default_width){
			this.setWidth( Smokeping_ui_Graph_default_width)
 			this.setHeight( Smokeping_ui_Graph_default_height);
		} 
		else {
            this.setWidth('auto');
			this.setHeight('auto');
		};
		this.set({
			border : new qx.ui.core.Border(1,'dotted','#ffffff'),
		    horizontalChildrenAlign: 'center',
	        verticalChildrenAlign: 'middle'
		});
		this._highlight();
		var loader = new Smokeping.ui.LoadingAnimation();
    	this.add(loader);
		this._preloader = qx.io.image.PreloaderManager.getInstance().create(this._src+';w='+this._width+';h='+this._height);
		if (this._preloader.isLoaded()){
			qx.client.Timer.once(this._image_loader,this,0);
		} else {
			this._preloader.addEventListener('load', this._image_loader, this);
		}
		this.addEventListener('mouseover',this._highlight,this);
		this.addEventListener('mouseout',this._unhighlight,this);
	},

	members: {
		_image_loader: function(e) {					
			 Smokeping_ui_Graph_default_width = this._preloader.getWidth();
			 Smokeping_ui_Graph_default_height = this._preloader.getHeight();
			var image = new qx.ui.basic.Image();
			image.setPreloader(this._preloader);
            qx.io.image.PreloaderManager.getInstance().remove(this._preloader);
			with(this){
				removeAll();
				add(image);
				addEventListener('click',this._open_navigator,this);
				_unhighlight();
			}
		},
		_open_navigator: function(e){
			with(this){
				setEnabled(false);
				_unhighlight();
				this._window = new Smokeping.ui.Navigator(this._src,this._width,this._height);
				_window.addToDocument();
				_window.positionRelativeTo(getElement(),2,-4);
				addEventListener('beforeDisappear',_kill_window,this);
				_window.open();
				_window.addEventListener('beforeDisappear',_close_window,this);
			}
		},
		_close_window: function(e){
			this.setEnabled(true);
		},
		_kill_window: function(e){
			this._window.close();
			this._window.dispose();
		},
		_highlight: function(e){	
			this.setBackgroundColor('#f8f8f8');
			this.getBorder().set({
				color: '#808080'
			});
		},
		_unhighlight: function(e){
			this.setBackgroundColor('transparent');
			this.getBorder().set({
				color: '#ffffff'
			});
		}
	}
	

});
 
 

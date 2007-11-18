/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * Zoom into the graph
 */

qx.Class.define('Smokeping.ui.Zoomer',
{
    extend: qx.ui.layout.CanvasLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param width   {Integer}   Width of the canvas
     *
     * @param height  {Integer}   Height ot the canvas
     *
     * @param right   {Integer}   Distance from the right edge
     *
     * @param top     {Integer}   Dist from the top
     *
     */

    construct: function (width,height,top,right) {
		this._width = width;
		this._height = height;
		this._top = top;
		this._right = right;
		with(this){
			base(arguments);
			set({
				width:		  '100%',
				height:		  '100%'
			});
		}
        var zoomer_defaults = {
            visibility: false,             
            opacity: 0.1,         
            backgroundColor: 'black',         
            overflow: 'hidden' // important to make box go to 'zero height' on ie6
        };
	    var dir = ['left','right','top','bottom' ];
	    for(var i=0;i<dir.length;i++){
			this._zoomer[dir[i]] = new qx.ui.basic.Terminator();    
	        this._zoomer[dir[i]].set(zoomer_defaults);
	        this.add(this._zoomer[dir[i]]);
		}

        this._zoomer['frame'] = new qx.ui.basic.Terminator();    
        this._zoomer['frame'].set(zoomer_defaults);
        this._zoomer['frame'].set({
			opacity: 1,
            backgroundColor: 'transparent',
            border: new qx.ui.core.Border(1,'dotted','#808080')			
        });

		this.add(this._zoomer['frame']);

		this.addEventListener("mousedown", this._zoom_start,this);
        this.addEventListener("mousemove", this._zoom_move,this);
        this.addEventListener("mouseup",   this._zoom_stop,this);
    },

	members: {
		_init_cache: function(){
	        var el = this.getElement();
	        this._page_left = qx.html.Location.getPageAreaLeft(el);
	        this._page_top = qx.html.Location.getPageAreaTop(el);
			this._image_width = qx.html.Location.getPageAreaWidth(el);
	        this._image_height = qx.html.Location.getPageAreaHeight(el);
            this._canvas_top = this._top;
	        this._canvas_left = this._image_width-this._width-this._right;
	        this._canvas_right = this._right;
            this._canvas_bottom = this._image_height-this._height-this._top;
		},

		_zoom_start: function(e){
			var z = this._zoomer;
			this._init_cache();	
            var mouse_y = e.getPageY()-this._page_top;
			var mouse_x = e.getPageX()-this._page_left;

            if (mouse_y < this._canvas_top) {
                mouse_y = this._canvas_top;
            }
            if (mouse_y > this._canvas_top + this._height) {
                mouse_y = this._canvas_top + this._height;
            }

            this._selector_start_y = mouse_y;
 
            this.setCapture(true);                                    

            z['top'].set({
				left: this._canvas_left,
		        width: this._width,
                top: 0,
                height: mouse_y,
                visibility: true
			});

            z['bottom'].set({
                left: this._canvas_left,
                width: this._width,
                height: this._image_height - mouse_y,
                top: mouse_y,
                visibility: true
			});

			z['left'].set({
                width: this._canvas_left,
                height: this._image_height,
                visibility: true
            });

            z['right'].set({
				left: this._image_width - this._canvas_right,
                width: this._canvas_right,
                height: this._image_height,
			    visibility: true
			});

            z['frame'].set({
				left: this._canvas_left,
			    width: this._width,
                top: mouse_y,
				visibility: true
			});			
		},

		_zoom_move: function(e){
			var z = this._zoomer;
            if (plot.getCapture()){        
	            var mouse_y = e.getPageY()-this._page_top;
				var mouse_x = e.getPageX()-this._page_left;
	
    	        if (mouse_y < this._canvas_top) {
        	        mouse_y = this._canvas_top;
            	}
            	if (mouse_y > this._canvas_top + this._height) {
                	mouse_y = this._canvas_top + this._height;
	            }

                if (mouse_y > this._selector_start_y) {
                    z['bottom'].set({
						height: this._image_height - mouse_y,
						top:    mouse_y
					});
                } else {
                    z['top'].setHeight(mouse_y);
                }   
                z['frame'].set({
					top: z['top'].getHeight(),
                    height: z['bottom'].getTop()-z['top'].getHeight()
				});
			}
		},
		_zoom_end: function(e){
			var z = this._zoomer;
			this.setCapture(false);
            z['top'].setVisibility(false);
            z['left'].setVisibility(false);
            z['right'].setVisibility(false);
            z['bottom'].setVisibility(false);
            z['frame'].setVisibility(false);
 
            if (z['bottom'].getTop() == z['top'].getTop()+z['top'].getHeight()){
                this._zoom_factor_top = 0;
                this._zoom_factor_bottom = 0;
            }
            else {
                var prev_factor = 1 - this._zoom_factor_top - this._zoom_factor_bottom; 
                this._zoom_factor_top = 
					(z['top'].getHeight()-this._canvas_top)/this._height * prev_factor
                        + this._zoom_factor_top;
                this.zoom_factor_bottom =
                    (z['bottom'].getHeight()-this._canvas_bottom)/this._height * prev_factor
                        + this._zoom_factor_bottom;
             }
		}
	}


});
 
 

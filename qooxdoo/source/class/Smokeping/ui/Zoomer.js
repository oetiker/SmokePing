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

    construct: function (target,width,height,top,right) {
        this.debug('hell');
        this._target = target;
		this._width = width;
		this._height = height+1; // some where the calc is 1 off. this fixes it
		this._top = top;
		this._right = right;
		with(this){
			base(arguments);
			set({
				width:		  '100%',
				height:		  '100%',
                visibility:   false
			});
		}
        var zoomer_defaults = {
            backgroundColor: 'black',
            opacity: 0.1,
            overflow: 'hidden' // important to make box go to 'zero height' on ie6
        };
	    var dir = ['left','right','top','bottom' ];
        var z = [];
        this._zoomer = z;
	    for(var i=0;i<dir.length;i++){
			z[dir[i]] = new qx.ui.basic.Terminator();    
	        z[dir[i]].set(zoomer_defaults);
	        this.add(z[dir[i]]);
		}
        
        z['frame'] = new qx.ui.basic.Terminator();    
        z['frame'].set(zoomer_defaults);
        z['frame'].set({
			opacity: 1,
            backgroundColor: 'transparent',
            border: new qx.ui.core.Border(1,'dotted','#808080')			
        });
        
		this.add(z['frame']);

  		this._target.addEventListener("mousedown", this._zoom_start,this);
        this._target.addEventListener("mousemove", this._zoom_move,this);
        this._target.addEventListener("mouseup",   this._zoom_end,this);
        this.debug('got zoomer');
    },

	members: {
		_init_cache: function(){
	        var el = this._target.getElement();
	        this._page_left = qx.html.Location.getPageAreaLeft(el);
	        this._page_top = qx.html.Location.getPageAreaTop(el);
			this._image_width = qx.html.Location.getPageAreaRight(el) - this._page_left;
	        this._image_height = qx.html.Location.getPageAreaBottom(el) - this._page_top ;
            this._canvas_top = this._top;
	        this._canvas_left = this._image_width-this._width-this._right;
	        this._canvas_right = this._right;
            this._canvas_bottom = this._image_height-this._height-this._top;
		},

		_zoom_start: function(e){
			var z = this._zoomer;
			this._init_cache();	
            var mouse_y = e.getPageY()-this._page_top;
//			var mouse_x = e.getPageX()-this._page_left;

            if (mouse_y < this._canvas_top) {
                mouse_y = this._canvas_top;
            }
            if (mouse_y > this._canvas_top + this._height) {
                mouse_y = this._canvas_top + this._height;
            }

            this._selector_start_y = mouse_y;
 
            this._target.setCapture(true);                                    

            z['top'].set({
				left: this._canvas_left,
		        width: this._width,
                top: 0,
                height: mouse_y
			});
	        this.debug(mouse_y);
	        this.debug(z['top'].getWidth());
	        this.debug(z['top'].getLeft());;
	        this.debug(z['top'].getTop());;
	        this.debug(z['top'].getHeight());;
                        
            z['bottom'].set({
                left: this._canvas_left,
                width: this._width,
                height: this._image_height - mouse_y,
                top: mouse_y
			});

			z['left'].set({
                width: this._canvas_left,
                height: this._image_height
            });

            z['right'].set({
				left: this._image_width - this._canvas_right,
                width: this._canvas_right,
                height: this._image_height
			});

            z['frame'].set({
				left: this._canvas_left,
			    width: this._width,
                top: mouse_y
			});			
            this.setVisibility(true);
    	},

		_zoom_move: function(e){
			var z = this._zoomer;
            if (this._target.getCapture()){        
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
			this._target.setCapture(false);
            this.setVisibility(false);

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
 
 

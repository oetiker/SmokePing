/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * Lets you do google map like draging of the graph canvas along time axis
 *
 */

qx.Class.define('Smokeping.ui.Mover',
{
    extend: qx.ui.layout.CanvasLayout,        
	include: Smokeping.ui.MPosition,

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param target  {Widget}    What surface should we base our selection on
     *
     * @param width   {Integer}   Width of the 'interesting' area of the target
     *
     * @param height  {Integer}   Height ot the 'interesting' area of the target
     *
     * @param right   {Integer}   Distance from the right edge
     *
     * @param top     {Integer}   Distance from the top
     *
	 * The zoomer will not activate if the ctrl key is pressed. This allows
     * for the Mover to act on these events
     *
     */

    construct: function (target,src,width,height,top,right,start,end) {
        this._target = target;
		this._src = src;
		this._width = width;
		this._height = height;
		this._top = top;
		this._right = right;
		this._start = start;
		this._end = end;
		with(this){
			base(arguments);
			set({
				width:		  width,
				height:		  height+17,
				top: 	      top-2,
				right:        right,
                visibility:   false,
				overflow:	  'hidden',
				backgroundColor: 'white'
			});
		}
		// make the canvas large
		
		this._moveing = false;
  		this._target.addEventListener("mousedown", this._move_start,this);
        this._target.addEventListener("mousemove", this._move_move,this);
        this._target.addEventListener("mouseup",   this._move_end,this);
    },

	members: {
    	_move_start: function(e){			
			if (!e.isCtrlPressed()) return;
			this._init_cache();
			this._moveing = true;
            this._start_x =  e.getPageX();
            this._target.setCapture(true);                                    
			this.removeAll();
			for (var i=0;i<4;i++){
				var duration = (this._end-this._start);
				var tile = new qx.ui.basic.Image();
				tile.set({
					top: -(this._top-2),
					left: -this._canvas_left,				
					clipTop: this._top-2,
					clipLeft: this._canvas_left,
					clipWidth: this._width,
					width: this._width,
					height: this._height+17,
					left: this._width * i,
					source: this._src+';w='+this._width+';h='+this._height+';s='+(this._start+(duration*(i-2)))+';e='+(this._end+(duration*(i-2)))
				});
				this.add(tile);
			}			
			this.setScrollLeft(2*this._width);
            this.setVisibility(true);
            this._move_move(e);
    	},

		_move_move: function(e){
            if (this._target.getCapture() && this._moveing ){        
				var drag_x = e.getPageX() - this._start_x;
				this.setScrollLeft(-drag_x+this._width*2);
			}
		},
		_move_end: function(e){
			if (!this._moveing) return;
			this._moveing = false;
			this._target.setCapture(false);
            this.setVisibility(false);
		}
	}


});
 
 

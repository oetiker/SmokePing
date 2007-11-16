package Qooxdoo::Services::Smokeping;
use strict;

sub GetAccessibility {
        return "public";
}

sub method_get_tree
{
    my $error = shift;
#    $error->set_error(101,$err);
#    return $error;
    return [['fk1','Folder 1',
	  	'fk1/f1','File 1',
	     	'fk1/f2','File 2',
		 [ 'fk1/sf1','Sub Folder 2',
		   'fk1/sf1/f3','File 3',	
		   'fk1/sf1/f4','File 4',
		   'fk1/sf1/f6','File 3',	
		   'fk1/sf1/f7','File 4',
		   'fk1/sf1/f8','File 3',	
		   'fk1/sf1/f9','File 4',
		   'fk1/sf1/f10','File 3',	
		   'fk1/sf1/f11','File 4',
		 ], 
               ],
               [ 'fk24','Folder 2',
   	         'fk24/sf1/f9','File 1',
	       ],
	       [ 'fk3','Folder 3',
                      'fk3/f3','File 33',
		      'fk3/f4','File 44',
                      'fk3/f6','File 33',
		      'fk3/f7','File 44', 
	       ]		
	   ]
}

1;


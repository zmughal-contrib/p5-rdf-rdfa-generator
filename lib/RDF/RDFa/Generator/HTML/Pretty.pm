package RDF::RDFa::Generator::HTML::Pretty;

use 5.008;
use base qw'RDF::RDFa::Generator::HTML::Hidden';
use common::sense;
use constant XHTML_NS => 'http://www.w3.org/1999/xhtml';
use Icon::FamFamFam::Silk;
use XML::LibXML qw':all';

sub create_document
{
	my ($proto, $model) = @_;
	my $self = (ref $proto) ? $proto : $proto->new;
	
	my $html = sprintf(<<HTML, ($self->{'version'}||'1.0'), ($self->{'title'} || 'RDFa Document'), ref $self);
<html xmlns="http://www.w3.org/1999/xhtml" version="XHTML+RDFa %1\$s">
<head profile="http://www.w3.org/1999/xhtml/vocab">
<title>%2\$s</title>
<meta nane="generator" value="%3\$s" />
</head>
<body>
<h1>%2\$s</h1>
<p><small>Generated by %3\$s.</small></p>
</body>
</html>
HTML

	return $proto->inject_document($html, $model);
}

sub nodes
{
	my ($proto, $model) = @_;
	my $self = (ref $proto) ? $proto : $proto->new;
	
	my $stream = $self->_get_stream($model);
	my @nodes;
	
	my $root_node = XML::LibXML::Element->new('div');
	$root_node->setNamespace(XHTML_NS, undef, 1);
	
	my $prefixes = {};
	my $subjects = {};
	while (my $st = $stream->next)
	{
		my $s = $st->subject->is_resource ?
			$st->subject->uri :
			('_:'.$st->subject->blank_identifier);
		push @{ $subjects->{$s} }, $st;
	}
	
	foreach my $s (keys %$subjects)
	{
		my $subject_node = $root_node->addNewChild(XHTML_NS, 'div');
		
		$self->_process_subject($subjects->{$s}->[0], $subject_node, $prefixes);
		$self->_resource_heading($subjects->{$s}->[0]->subject, $subject_node, $subjects->{$s}, $prefixes);
		$self->_resource_classes($subjects->{$s}->[0]->subject, $subject_node, $subjects->{$s}, $prefixes);
		$self->_resource_statements($subjects->{$s}->[0]->subject, $subject_node, $subjects->{$s}, $prefixes);
		## TODO Query $model for statements that act as special notes for the subject (in a separate graph)
		#$self->_resource_notes($subjects->{$s}->[0]->subject, $subject_node, $model);
	}
	
	if ($self->{'version'} == 1.1
	and $self->{'prefix_attr'})
	{
		my $prefix_string = '';
		while (my ($u,$p) = each(%$prefixes))
		{
			$prefix_string .= sprintf("%s: %s ", $p, $u);
		}
		if (length $prefix_string)
		{
			$root_node->setAttribute('prefix', $prefix_string);
		}
	}
	else
	{
		while (my ($u,$p) = each(%$prefixes))
		{
			$root_node->setNamespace($u, $p, 0);
		}
	}
	
	push @nodes, $root_node;
	return @nodes if wantarray;
	my $nodelist = XML::LibXML::NodeList->new;
	$nodelist->push(@nodes);
	return $nodelist;
}

sub _resource_heading
{
	my ($self, $subject, $node, $statements, $prefixes) = @_;
	
	my $heading = $node->addNewChild(XHTML_NS, 'h3');
	$heading->appendTextNode( $subject->is_resource ? $subject->uri : ('_:'.$subject->blank_identifier) );
	$heading->setAttribute('class', $subject->is_resource ? 'resource' : 'blank' );
	
	return $self;
}

## TODO
## <span rel="rdf:type"><img about="[foaf:Person]" src="fsfwfwfr.png"
##                           title="http://xmlns.com/foaf/0.1/Person" /></span>

sub _resource_classes
{
	my ($self, $subject, $node, $statements, $prefixes) = @_;
	
	my @statements = sort {
		$a->predicate->uri cmp $b->predicate->uri
		or $a->object->uri cmp $b->object->uri
		}
		grep {
			$_->predicate->uri eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
			and $_->object->is_resource
		}
		@$statements;

	return unless @statements;

	my $SPAN = $node->addNewChild(XHTML_NS, 'span');
	$SPAN->setAttribute('class', 'rdf-type');
	$SPAN->setAttribute('rel', $self->_make_curie('http://www.w3.org/1999/02/22-rdf-syntax-ns#type', $prefixes));

	foreach my $st (@statements)
	{
		my $IMG = $SPAN->addNewChild(XHTML_NS, 'img');
		$IMG->setAttribute('about', $st->object->uri);
		$IMG->setAttribute('alt',   $st->object->uri);
		$IMG->setAttribute('src',   $self->_img($st->object->uri));
		$IMG->setAttribute('title', $st->object->uri);
	}

	return $self;
}


sub _resource_statements
{
	my ($self, $subject, $node, $statements, $prefixes) = @_;
	
	my @statements = sort {
		$a->predicate->uri cmp $b->predicate->uri
		or $a->object->uri cmp $b->object->uri
		}
		grep {
			$_->predicate->uri ne 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
			or !$_->object->is_resource
		}
		@$statements;

	return unless @statements;
	
	my $DL = $node->addNewChild(XHTML_NS, 'dl');
	
	my $current_property = undef;
	foreach my $st (@statements)
	{
		unless ($st->predicate->uri eq $current_property)
		{
			my $DT = $DL->addNewChild(XHTML_NS, 'dt');
			$DT->setAttribute('title', $st->predicate->uri);
			$DT->appendTextNode($self->_make_curie($st->predicate->uri, $prefixes));
		}
		
		my $DD = $DL->addNewChild(XHTML_NS, 'dd');
		
		if ($st->object->is_resource)
		{
			$DD->setAttribute('rel',  $self->_make_curie($st->predicate->uri, $prefixes));
			$DD->setAttribute('class', 'resource');
			
			my $A = $DD->addNewChild(XHTML_NS, 'a');
			$A->setAttribute('href', $st->object->uri);
			$A->appendTextNode($st->object->uri);
		}
		elsif ($st->object->is_blank)
		{
			$DD->setAttribute('rel',  $self->_make_curie($st->predicate->uri, $prefixes));
			$DD->setAttribute('class', 'blank');
			
			my $A = $DD->addNewChild(XHTML_NS, 'span');
			$A->setAttribute('about', '[_:'.$st->object->blank_identifier.']');
			$A->appendTextNode('_:'.$st->object->blank_identifier);
		}
		elsif ($st->object->is_literal
		&& !$st->object->has_datatype)
		{
			$DD->setAttribute('property',  $self->_make_curie($st->predicate->uri, $prefixes));
			$DD->setAttribute('class', 'plain-literal');
			$DD->setAttribute('xml:lang',  $st->object->literal_value_language);
			$DD->appendTextNode($st->object->literal_value);
		}
		elsif ($st->object->is_literal
		&& $st->object->has_datatype
		&& $st->object->literal_datatype eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral')
		{
			$DD->setAttribute('property',  $self->_make_curie($st->predicate->uri, $prefixes));
			$DD->setAttribute('class', 'typed-literal datatype-xmlliteral');
			$DD->setAttribute('datatype',  $self->_make_curie($st->object->literal_datatype, $prefixes));
			$DD->appendWellBalancedChunk($st->object->literal_value);
		}
		elsif ($st->object->is_literal
		&& $st->object->has_datatype)
		{
			$DD->setAttribute('property',  $self->_make_curie($st->predicate->uri, $prefixes));
			$DD->setAttribute('class', 'typed-literal');
			$DD->setAttribute('datatype',  $self->_make_curie($st->object->literal_datatype, $prefixes));
			$DD->appendTextNode($st->object->literal_value);
		}
	}
	
	return $self;
}

sub _img
{
	my ($self, $type) = @_;
	
	my $icons = {
		'http://xmlns.com/foaf/0.1/Document'                   => 'page_white_text',
		'http://xmlns.com/foaf/0.1/Person'                     => 'user',
		'http://xmlns.com/foaf/0.1/Group'                      => 'group',
		'http://xmlns.com/foaf/0.1/Organization'               => 'chart_organisation',
		'http://xmlns.com/foaf/0.1/Image'                      => 'image',
		'http://www.w3.org/2006/vcard/ns#Vcard'                => 'vcard',
		'http://www.w3.org/2006/vcard/ns#Address'              => 'house',
		'http://www.w3.org/2006/vcard/ns#Location'             => 'world', 
		'http://www.w3.org/2002/12/cal/ical#Vcalendar'         => 'calendar',
		'http://www.w3.org/2002/12/cal/ical#Vevent'            => 'date',
		'http://purl.org/rss/1.0/channel'                      => 'feed',
		'http://purl.org/rss/1.0/item'                         => 'page_white_link' ,
		'http://bblfish.net/work/atom-owl/2006-06-06/#Feed'    => 'feed',
		'http://bblfish.net/work/atom-owl/2006-06-06/#Entry'   => 'page_white_link',
		'http://www.w3.org/2003/01/geo/wgs84_pos#SpatialThing' => 'world',
		'http://www.w3.org/2003/01/geo/wgs84_pos#Point'        => 'world', 
		'http://purl.org/NET/c4dm/event.owl#Event'             => 'date',
		'http://www.holygoat.co.uk/owl/redwood/0.1/tags/Tag'   => 'tag_blue',
		'http://www.holygoat.co.uk/owl/redwood/0.1/tags/Tagging' => 'tag_blue_add',
		'http://commontag.org/ns#Tag'                          => 'tag_blue',
		'http://commontag.org/ns#AutoTag'                      => 'tag_red',
		'http://commontag.org/ns#AuthorTag'                    => 'tag_green',
		'http://commontag.org/ns#ReaderTag'                    => 'tag_yellow',
		'http://usefulinc.com/ns/doap#Project'                 => 'application_xp_terminal',
		'http://purl.org/goodrelations/v1#PriceSpecification'  => 'money',
		'http://www.w3.org/ns/auth/rsa#RSAPublicKey'           => 'key',
		'http://purl.org/ontology/bibo/Book'                   => 'book',
		'http://purl.org/NET/book/vocab#Book'                  => 'book',
		'http://purl.org/stuff/rev#Review'                     => 'award_star_gold_1',
		'http://rdf.data-vocabulary.org/#Person'               => 'user',
		'http://rdf.data-vocabulary.org/#Organization'         => 'chart_organisation',
		'http://rdf.data-vocabulary.org/#Review'               => 'award_star_gold_1',
		'http://rdf.data-vocabulary.org/#Review-aggregate'     => 'award_star_add',
	};
	
	return Icon::FamFamFam::Silk->new($icons->{$type}||'asterisk_yellow')->uri;
}

1;

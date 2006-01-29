=begin comment
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

File:
	Telephony_xAP.pm

Description:
	xAP Listener for Telephony Events (Based on CID.Meteor Schema)
	
Author:
	Jason Sharpee
	jason@sharpee.com

License:
	This free software is licensed under the terms of the GNU public license.

Usage:

	Example initialization:

		use Telephony_xAP;

		$tel = new Telephony_xAP();

        Note: A recent change was added to support more current xAP schema.  Specifically,
              these include the CID.Meteor and CTI.* schemas.  In addition, these
              changes utilize xAP subaddresses (aka endpoints) to determine "line".

              Sample initialization to incorporate these changes follows:
           
              $xap_meteor_item = new xAP_Item('CID.Meteor');
              $xap_cti_item = new xAP_Item('CTI.*');
              $tel = new Telephony_xAP($xap_meteor_item); # overrule the default behavior
              $tel->add_xap_item($xap_cti_item);

	Input states:

	Output states:
		"CID"		- CallerID is available
		<input states>  - All input states are echoed exactly to the output state as 
				  well.


Bugs:
	- Does not handle all telephony events right now. 
	- Call logging will be implemented next

Special Thanks to: 
	Bruce Winter - MH
		

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
=cut

use xAP_Items;
package Telephony_xAP;
@Telephony_xAP::ISA = ('Telephony_Item');

my ($m_xap, %phone_line_names);

#Initialize class
sub new 
{
	my ($class,$p_xap) = @_;
	my $self={};
	bless $self, $class;

	#&xAP::startup if $Reload;
        if (!($p_xap)) {
	   $p_xap = new xAP_Item('Telephony.Info');
	   &main::store_object_data($p_xap,'xAP_Item','Telephony','Telephony');
        } else {
           print "Initializing Telephony_xAP with xAP object: " . $p_xap->class_name() . "\n";
        }
        $$self{xap_listeners}{$p_xap->class_name()} = $p_xap;
        $$self{xap_listeners}{$p_xap->class_name()}->tie_items($self);

#	$$self{m_xap} = $p_xap if defined $p_xap;
#	$$self{m_xap}->tie_items($self);
        $$self{call_duration} = 0;
        $$self{vm}{changed} = undef;

        # init phone_line_names unless already init'd
        &main::read_parm_hash(\%phone_line_names, $main::config_parms{phone_line_names})
           unless %phone_line_names;

	return $self;
}

sub xap_item
{
	my ($self, $p_class_name) = @_;
        for my $class_name (keys %{$$self{xap_listeners}}) {
           if (!($p_class_name) || ($class_name eq $p_class_name)) {
              return $$self{xap_listeners}{$class_name};
           }
        }
	return undef;
}

sub add_xap_item
{
        my ($self, $p_xap) = @_;
        $xap_listeners{$p_xap->class_name()} = $p_xap;
}

sub outgoing_hook
{
	my ($self,$p_xap)= @_;
	
        $self->cid_number($$p_xap{'outgoing.callcomplete'}{phone});
	$self->address($$p_xap{'outgoing.callcomplete'}{line});
	$self->cid_name('Unknown');
	$self->cid_type('N');
	return 'dialed';

}

sub meteor_out_complete_hook
{
	my ($self,$p_xap)= @_;
	
        $self->cid_number($$p_xap{'outgoing.callcomplete'}{phone});
	$self->address($self->get_line($p_xap));
	$self->cid_name('Unknown');
	$self->cid_type('N');
	return 'dialed';

}

sub callerid_hook
{
	my ($self,$p_xap)= @_;
#	foreach (keys %{$$p_xap{'incoming.callwithcid'}}) {
#		&::print_log("Keys: $_");
#	}
	#CLEAR
	$self->cid_name('');
	$self->cid_number('');
	$self->cid_type('');
	$self->cid_name($$p_xap{'incoming.callwithcid'}{name});
        $self->cid_number($$p_xap{'incoming.callwithcid'}{phone});
        $self->cid_type('N'); # N-Normal, P-Private/Blocked, U-Unknown;
#	&::print_log("CID=====". $$p_xap{'incoming.callwithcid'}{rnname} );
	if (uc $$p_xap{'incoming.callwithcid'}{rnnumber} eq 'UNAVAILABLE' or 
		uc $$p_xap{'incoming.callwithcid'}{rnnumber} eq 'WITHHELD' ) {
	        $self->cid_type('U'); # N-Normal, P-Private/Blocked, U-Unknown;
	}	
	$self->address($$p_xap{'incoming.callwithcid'}{line});
#	&::print_log("CID====" . $self->cid_number());
	return "cid";
}

sub meteor_in_cid_hook
{
	my ($self,$p_xap)= @_;
	$self->cid_name('');
	$self->cid_number('');
	$self->cid_type('');
	$self->cid_name($$p_xap{'incoming.callwithcid'}{name});
        $self->cid_number($$p_xap{'incoming.callwithcid'}{phone});
        $self->cid_type('N'); # N-Normal, P-Private/Blocked, U-Unknown;
#	&::print_log("CID=====". $$p_xap{'incoming.callwithcid'}{rnname} );
	if (uc $$p_xap{'incoming.callwithcid'}{rnnumber} eq 'UNAVAILABLE' or 
		uc $$p_xap{'incoming.callwithcid'}{rnnumber} eq 'WITHHELD' ) {
	        $self->cid_type('U'); # N-Normal, P-Private/Blocked, U-Unknown;
	}	
	$self->address($self->get_line($p_xap));
#	&::print_log("CID====" . $self->cid_number());
	return "cid";
}

sub cti_mwi_hook
{
	my ($self,$p_xap)= @_;
        # extract the mailbox name from the subaddress
        my $subaddress = $p_xap->source() =~ /.+\:(.+)/;
        my ($vmlabel, $group, $mailboxname) = split(/\./, $subaddress);
        # for now, we'll concatenate the group and mailbox name back into the asterisk form
        my $mailboxlabel = $mailboxname . '@' . $group;
        my $totalmessages = $$p_xap{mwi}{totalmessages};
        my $readmessages = $$p_xap{mwi}{readmessages};
        if (($totalmessages) && ($readmessages)) {
           $self->mwi($mailboxlabel, $totalmessages, $readmessages);
           return defined($self->mwi_changed()) ? 'mwi' : 'unknown';
        } else {
           return 'unknown';
        }
}

sub get_line 
{
	my ($self, $p_xap)= @_;
        # extract the mailbox name from the subaddress
	my $source = $$p_xap{'xap-header'}{source};
        my ($subaddress) = $source =~ /.+\:(.+)/;
        for my $line (keys %phone_line_names) {
           if ($subaddress eq $line) {
              return $phone_line_names{$line};
           }
        }
        return 'unknown';
}

sub set 
{
	my ($self, $p_state, $p_setby, $p_response) = @_;
	return if &main::check_for_tied_filters($self, $state);
        for $class_name (keys %{$$self{xap_listeners}}) {
           my $xap_listener = $$self{xap_listeners}{$class_name};
	   if ($p_setby eq $xap_listener ) {
              if (lc $class_name eq 'telephony.info') {
		 if (defined $xap_listener->state_now('incoming.callwithcid') ) {
			$state=$self->callerid_hook($p_setby);
		 } elsif (defined $xap_listener->state_now('outgoing.callcomplete') ) {
			$state=$self->outgoing_hook($p_setby);
		 }
#		 &::print_log("TXAP:$p_state:$p_setby:" . ${$$self{m_xap}}{'incoming.callwithcid'}{phone} . ":");

              } elsif (lc $class_name eq 'cid.meteor') {
		 if (defined $xap_listener->state_now('incoming.callwithcid') ) {
			$state=$self->meteor_in_cid_hook($p_setby);
		 } elsif (defined $xap_listener->state_now('outgoing.callcomplete') ) {
			$state=$self->meteor_out_complete_hook($p_setby);
		 }

              } elsif ($class_name =~ /cti/i) {
		 if (defined $xap_listener->state_now('mwi') ) {
			$state=$self->cti_mwi_hook($p_setby);
                 }
              }		
	   }	
        }


	# Always pass along the state to base class unless "unknown"
	$self->SUPER::set($state,$p_setby, $p_response) unless $state eq 'unknown';

	return;
}

sub patch
{
	my ($self,$p_state)= @_;

	return $self->SUPER::patch($p_state);
}

sub play
{
	my ($self,$p_file) = @_;

	$self->patch("on");
	&::play ($p_file);
	return $self->SUPER::play($p_file);
}

sub record
{
	my ($self,$p_file,$p_timeout) = @_;

#	&::rec ($p_file);  ????
	return $self->SUPER::rec($p_file,$p_timeout);
}

sub speak
{
	my ($self,%p_phrase) = @_;
	$self->patch('on');
	&::speak(%p_phrase);
#	Is there a way to know when speaking is finished?
#	$self->patch('off');
	return $self->SUPER::speak(%p_phrase);	

}
sub dtmf
{
	my ($self,$p_dtmf) = @_;
	
	return $self->SUPER::dtmf($p_dtmf);	
}

sub dtmf_sequence
{
	my ($self,$p_dtmf_seq) = @_;
	
	return $self->SUPER::dtmf_sequence($p_dtmf_seq);	
}

sub hook
{
	my ($self,$p_state) = @_;
	
	if ($p_state eq 'on')
	{
	}
	elsif (defined $p_state)
	{
	}
	return $self->SUPER::hook($p_state);
}

sub call_duration
{
   my ($self, $p_duration) = @_;
   $$self{call_duration} = $p_duration if defined($p_duration);
   return $$self{call_duration};
}

sub mwi
{
   my ($self, $p_mailbox, $p_totalmessages, $p_readmessages) = @_;
   if (defined($p_newmessages) && defined($p_readmessages)) {
      $$self{vm}{changed} = undef;
      if (!(exists($$self{vm}{$p_mailbox}))
          || ($$self{vm}{$p_mailbox}{totalmessages} != $p_totalmessages)
          || ($$self{vm}{$p_mailbox}{readmessages} != $p_readmessages)
      ) {
         $$self{vm}{changed}{mailbox} = $p_mailbox;
         $$self{vm}{changed}{totalmessages} = $p_totalmessages;
         $$self{vm}{changed}{readmessages} = $p_readmessages;
      }
      $$self{vm}{$p_mailbox}{totalmessages} = $p_totalmessages;
      $$self{vm}{$p_mailbox}{readmessages} = $p_readmessages;
   }
   if (($p_mailbox) && exists($$self{vm}{$p_mailbox})) {
      my %mwi_info = $$self{vm}{$p_mailbox};
      return %mwi_info;
   }
}

sub mwi_changed
{
   my ($self) = @_;
   if (defined($$self{vm}{changed})) {
      my %changed = $$self{vm}{changed};
      return %changed;
   } else {
      return undef;
   }
}

1;

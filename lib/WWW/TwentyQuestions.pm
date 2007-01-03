package WWW::TwentyQuestions;

# Documentation is at the end of the module code.

use strict;
use warnings;
use LWP::UserAgent;

our $VERSION = '0.01';

our $URI = {
	'start_en-us'     => 'http://www.20q.net/startg_enUS.html',
	'startplay_en-us' => 'http://y.20q.net/gsew-en',
};

sub new {
	my $class = shift;

	my $self = {
		debug    => 0,
		agent    => new LWP::UserAgent,
		userid   => undef,
		passwd   => undef,
		playing  => 0,
		lang     => 'en-us',
		choices  => {}, # temporary answer options for last question asked
		answers  => [], # temporary array of options
		question => undef, # last question asked
		on_error => sub {
			my ($q,$err) = @_;

			warn "WWW::TwentyQuestions Error: $err";
		},
	};
	$self->{agent}->agent ('Mozilla/4.0');

	bless ($self,$class);
	return $self;
}

sub setErrorHandler {
	my ($self,$ref) = @_;

	$self->{on_error} = $ref;
}

sub callError {
	my ($self,$err) = @_;
	if (defined $self->{on_error}) {
		&{$self->{on_error}} ($self,$err);
	}
}

sub debug {
	my ($self,$msg) = @_;

	if ($self->{debug} == 1) {
		print "$msg\n";
	}
}

sub request {
	my ($self,$method,$url,$args) = @_;

	$self->debug ("Request $method $url...");

	my $reply = undef;
	if ($method eq 'GET') {
		$reply = $self->{agent}->get ($url);
	}
	elsif ($method eq 'POST') {
		$reply = $self->{agent}->post ($url,$args);
	}

	if (defined $reply) {
		if ($reply->is_success) {
			return $reply->content;
		}
		else {
			$self->callError ("Could not access $url: " . $reply->status_line . "\n");
		}
	}
	else {
		$self->callError ("Unsupported HTTP method $method ?");
		return undef;
	}
}

sub dump {
	my ($self,$file,$info) = @_;

	return unless $self->{debug} == 1;

	open (FILE, ">$file");
	print FILE $info;
	close (FILE);

	use Data::Dumper;
	open (CORE, ">core.txt");
	print CORE Dumper($self);
	close (CORE);
}

sub start {
	my $self = shift;

	my $inf = {
		language => 'en-us',
		game     => 'classic',
		@_,
	};
	$self->{lang} = $inf->{language};

	my $url = $URI->{ "start_" . $inf->{language} };
	if (not defined $url) {
		warn "No URL for language $inf->{language}!";
		return undef;
	}

	# Get a username and password.
	my $login = $self->request ('GET', $url);
	($self->{userid}) = $login =~ /<input type=hidden name="userid" value="(.+?)"/i;
	($self->{passwd}) = $login =~ /<input type=hidden name="password" value="(.+?)" >/i;
	#print "Got user: $self->{userid}:$self->{passwd}\n";

	# Start the game.
	$url = $URI->{ "startplay_" . $inf->{language} };

	my $reply = $self->request ('POST',$url, {
		userid => $self->{userid},
		password => $self->{passwd},
		scgend   => 77,    # male; 70 = female
		scage    => 20,    # age
		scccode  => 21333, # United States
	});

	$self->dump ("start.html",$reply);

	# Get the first question.
	my ($firstq) = $reply =~ /<big><b>Q1. &nbsp;(.+?)<br>/i;
	if (not defined $firstq) {
		$self->callError ("First question not found!");
		return undef;
	}
	$firstq = "Q1.  $firstq";
	$self->{question} = $firstq;

	$self->{playing} = 1;

	# Get the choices.
	$self->{choices} = {};
	$self->{answers} = [];
	while ($reply =~ /<a href="\/gsew\-en\?(.+?)" target="mainFrame">(.+?)<\/a>/i) {
		my $label = $2;
		if ($label ne '<font color="#000033"><font size="+3"><b>?</b></font></font>') {
			push (@{$self->{answers}}, $label);
			$label = lc($label);
			$label =~ s/ //g;
			$self->{choices}->{$label} = $1;
		}
		$reply =~ s/<a href="\/gsew\-en\?(.+?)" target="mainFrame">(.+?)<\/a>//i;
	}

	#print "Answers: " . join (", ", keys %{$self->{choices}}) . "\n";
	return $firstq;
}

sub answer {
	my ($self,$answer) = @_;
	$answer = lc($answer);
	$answer =~ s/ //g;

	# Was it a valid answer?
	if (defined $self->{choices}->{$answer}) {
		# Find this answer's ID.
		my $id = $self->{choices}->{$answer};
		my $url = $URI->{ "startplay_" . $self->{lang} };
		my $reply = $self->request ('GET', "$url?$id");

		#print "Answer Chosen: $answer (id: $id)\n";
		#print "Reply Length: " . length $reply;

		# Get the next question.
		my ($number,$question) = $reply =~ /<big><b>Q(\d+)\. &nbsp;(.+?)<br>/i;

		$self->dump ("q.html",$reply);

		# If 20Q just made a guess and we responded...
		if ($answer eq 'right') {
			# See if 20Q won or if WE won.
			my $winner = 'unknown';
			if ($reply =~ /<h2>20Q won!<\/h2>/i) {
				$winner = '20Q Won!';
			}
			else {
				$winner = 'You won!';
			}

			my ($thinking) = $reply =~ /<big><b>You were thinking (.+?)<\/b><\/big>/i;
			$thinking = "You were thinking $thinking";

			# Not playing anymore.
			$self->{playing} = 0;
			$self->{question} = 'Start a new game to play!';
			$self->{answers} = [];
			$self->{choices} = {};
			return "$winner\n$thinking";
		}

		# If 20Q has given up and we won...
		if ($reply =~ /<h2>You won!<\/h2>/i) {
			my $winner = 'You won!';

			# Not playing anymore.
			$self->{playing} = 0;
			$self->{question} = 'Start a new game to play!';
			$self->{answers} = [];
			$self->{choices} = {};
			return "$winner\nYou have stumped 20Q!";
		}

		# See if this is a regular question or a guess at the answer.
		if ($reply =~ /<a href="\/gsew-en\?(.+?)">Right<\/a>\, <a href="\/gsew-en\?(.+?)">Wrong<\/a>\, <a href="\/gsew-en\?(.+?)"> Close <\/a> <br>/i) {
			print "##### 20Q is making a guess!\n";
			my $right = $1;
			my $wrong = $2;
			my $close = $3;

			$self->{choices} = {
				right => $right,
				wrong => $wrong,
				close => $close,
			};
			$self->{answers} = [ qw(Right Wrong Close) ];

			$self->{question} = "Q$number.  $question";
			return $self->{question};
		}

		# Get the new answers.
		$self->{choices} = {};
		$self->{answers} = [];
		while ($reply =~ /<a href="\/gsew\-en\?(.+?)" target="mainFrame">(.+?)<\/a>/i) {
			my $id    = $1;
			my $label = $2;
			if ($label ne '<font color="#000033"><font size="+3"><b>?</b></font></font>') {
				#print "Found answer: $label (id: $id)\n";
				$label =~ s/&nbsp;//g;
				push (@{$self->{answers}}, $label);
				$label = lc($label);
				$label =~ s/ //g;
				$self->{choices}->{$label} = $id;
			}
			$reply =~ s/<a href="\/gsew\-en\?(.+?)" target="mainFrame">(.+?)<\/a>//i;
		}

		$self->{question} = "Q$number.  $question";
		return $self->{question};
	}
	else {
		warn "Invalid answer\n";
		return $self->question;
	}
}

sub playing {
	return shift->{playing};
}

sub question {
	return shift->{question};
}

sub choices {
	return join (", ", @{shift->{answers}});
}

=head1 NAME

WWW::TwentyQuestions - Perl interface to the classic 20 Questions game as provided by 20Q.net

=head1 SYNOPSIS

  use WWW::TwentyQuestions;

  # Create a new object
  my $q = new WWW::TwentyQuestions;

  # Start a new game and get the first question
  # ("Is it an animal, vegetable, or mineral?")
  my $first = $q->start;

  # Print the first question and our options.
  print "$first\n"
    . $q->choices . "\n";

  # Loop while we're playing.
  while ($q->playing) {
    # Give the user a chance to answer.
    my $answer = <STDIN>;
    chomp $answer;

    # Send the answer into the game and get the next question
    # (or the same question if the answer was unacceptable)
    my $next = $q->answer ($answer);

    # Print the next question and our choices.
    print "$next\n"
      . $q->choices . "\n";

  }

  print "Game Over\n";

=head1 DESCRIPTION

This module serves as an interface to the Classic 20 Questions game as provided on
20Q.net. Currently the module only supports the English version of the Classic game;
the "20Q Music" and "20Q People" and other like games are *not* yet supported.

=head1 METHODS

=head2 new

Create a new instance of WWW::TwentyQuestions. The only argument you should pass is B<debug>. Before
doing so, take note of everything B<debug> is going to do. See L<"DEBUG MODE">.

=head2 setErrorHandler (CODEREF)

Set a custom error handler. If you are making a GUI frontend for 20Q, this will help your
program to respond to and show error messages when a console wouldn't be available. The
error handler receives C<($object,$error_string)> in C<@_>. The default handler is to just
warn the errors to STDERR.

=head2 start

Start a new game of 20 Questions. This method will return the first question, which is
typically as follows:

  Q1.  Is it classified as Animal, Vegetable or Mineral?

=head2 answer (ANSWER)

Answer the previously asked question. C<ANSWER> must be one of the answers allowed for
the previous question (see method C<choices> below).

This method will return the next question down the line. If the answer given was not
acceptible for the last question asked, the last question is returned from this method.

When the game comes to an end, this method will not return a new question, but will return
the final statement. This statement might look like either of these:

  20Q Won!
  You were thinking of a piranha.

  You won!
  You have stumped 20Q!

=head2 choices

Returns your list of choices in a comma-separated scalar. One of these values must be
given in an B<answer> to the last B<question>.

=head2 question

Returns (repeats) the last question that was asked by 20Q.

=head2 playing

Returns true if the game is currently in progress. This is best used as your main program
loop, as shown in the L<"SYNOPSIS">. As long as a question is pending a response, this
method returns true.

=head2 callError (ERRSTR) *Internal

This method provokes your error handler with a message.

=head2 debug (STRING) *Internal

This prints a debug message when debug mode is on.

=head2 request (METHOD, URL, ARGS) *Internal

Make an HTTP request. Returns the HTML content of the page if successful.

=head2 dump (FILENAME, DATA) *Internal

Dump HTML data C<DATA> into file C<FILENAME>. Also dumps the hash structure of the object
into the file C<core.txt>. Used in debug mode.

=head1 DEBUG MODE

When debug mode is activated:

  - Several debug messages are printed to STDOUT.
  - The "Start New Game" page and all subsequent question pages have their HTML codes
    dumped into start.html or q.html, respectfully.
  - All internal hash data is dumped into core.txt on every game request.

If your program needs files by the same names as these, use debug mode when in a safer
environment.

=head1 SEE ALSO

The official website of 20 Questions: http://www.20q.net/

=head1 CHANGES

  0.01  Sun Dec 24 19:54:46 2006
        - Original version.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 Casey Kirsle

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
1;
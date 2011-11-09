#!/usr/bin/perl

#   MusicFS - A FUSE-Filesystem for Audiofiles written in Perl
#   Copyright (C) 2009  Markus Keil <markuskeil@thereapman.net>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software Foundation,
#   Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

use warnings;
use strict;

use POSIX;
use Fuse;
use MP3::Tag;
use Ogg::Vorbis::Header;

$| = 1;
my $debug = "";


my $filesystem = {
    root =>
    {
        content =>
        {
            Genre =>
            {
                type => 'dir'
            },
            Artist =>
            {
                type => 'dir'
            },
            Album =>
            {
                type => 'dir'
            },
            Year =>
            {
                type => 'dir'
            },
            fsinfo =>
            {
                type => 'file',
                content => 'MusicFS - No Files found in basedir\n'
            }
        }
    }
};

my $lastAttredFile;

sub my_getattr {
    my ( $filename ) = @_;
    &print_debug("==ATTRIBUTES==>$filename ");

    # regulaere Datei
    my $type = 0100;

    # owner: r/w, group: r, others: r
    my $bits = 0444;

    # falls Verzeichnis, type auf dir setzen,
    # mode auf 0755:
    # owner: r/w/x, group: r/x, others: r/x
    my $current = $filesystem->{'root'}->{'content'};
    my @pathElements = split( '/', $filename );
    my $currentType = 'file';

    if ( @pathElements > 1 ) {
        foreach my $pathElement ( @pathElements[1..$#pathElements] ) {

            if ( !defined( $current->{$pathElement} ) ) {
                &print_debug("not found!\n");
                return -1*ENOENT;
            }
            $currentType = $current->{$pathElement}->{'type'};
            $lastAttredFile = $current->{$pathElement} if ( $currentType eq 'file' );

            $current = $current->{$pathElement}->{'content'} if ( $currentType eq 'dir' );
        }
    }

    if ( $filename eq '/' || $currentType eq 'dir' ) {
        $type = 0040;
        $bits = 0555;
    } 
    
    #my $mode = $type << 9 | $bits;
    my $mode = $type << 9 | $bits;
    my $nlink = 1;

    # reale UID (siehe perlvar)
    my $uid = $<;

    # reale GID (siehe perlvar)
    my ($gid) = split / /, $(;

    # Geraete-ID (special files only)
    my $rdev = 0;

    # letzter Zugriff
    my $atime = time;

    # GroeÃe
    my $size = 0;

    if ( $currentType eq 'file' && $filename ne '/' && $filename ne '/fsinfo')  {
        $size =  -s $lastAttredFile->{'content'};
    }

    if ( $filename eq '/fsinfo' )
    {
        $size = length($lastAttredFile->{'content'});
    }
    
    if ( $filename =~ /.*folder.jpg/igo )
    {
        $size = length($lastAttredFile->{'content'});
    }

    # letzte Aenderung
    my $mtime = $atime;

    # letzte Aenderung Inode
    my $ctime = $atime;

    my $blksize = 1024;
    my $blocks = 1;
    
    my $dev = 0;
    my $ino = 0;
    &print_debug("is a $currentType of size $size Bytes\n");
    return ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks );
}

sub my_getdir {
    my ( $filename ) = @_;
    &print_debug("==GETDIR==>$filename\n");

    my $current = $filesystem->{'root'}->{'content'};
    my @pathElements = split( '/', $filename );

    if ( @pathElements > 1 ) {
        foreach my $pathElement ( @pathElements[1..$#pathElements] ) {
            return( -1*ENOENT ) if ( !defined( $current->{$pathElement} ) );
            $current = $current->{$pathElement}->{'content'};
        }
    }

    return( '.', keys( %{$current} ), 0 );
}

sub my_read {
    my ( $filename, $reqsize, $offset ) = @_;
    my $return;
    
    my $current = $filesystem->{'root'}->{'content'};
    my @pathElements = split( '/', $filename );
    my $currentType = 'dir';

    if ( @pathElements > 1 ) {
        foreach my $pathElement ( @pathElements[1..$#pathElements] ) {

            if ( !defined( $current->{$pathElement} ) ) {
                &print_debug("==READING==>$filename not found!\n");
                return -1*ENOENT;
            }
            $currentType = $current->{$pathElement}->{'type'};
            $lastAttredFile = $current->{$pathElement} if ( $currentType eq 'file' );

            $current = $current->{$pathElement}->{'content'} if ( $currentType eq 'dir' );
        }
    }
    
    if($filename eq "/fsinfo")
    {
        $return = $lastAttredFile->{'content'};
        &print_debug("==READING==> Filesystem Statisticsfile requested\n");
    }
    elsif($filename =~ /.*folder\.jpg/)
    {
        &print_debug("==READING==>$filename ($reqsize bytes from offset $offset)\n");
        $return = $lastAttredFile->{'content'};
    }
    else
    {
        my $original_file = $lastAttredFile->{'content'};
        open(ORG, $original_file);
        binmode(ORG);
        seek(ORG, $offset,1);
        my $readed = read(ORG,$return,$reqsize);
    
        close(ORG);
        &print_debug("==READING==>$original_file ($reqsize bytes from offset $offset >> $readed bytes readed)\n");
    }
        
    return $return;
}


sub print_debug {
    if($debug eq "debug")
    {
        my $msg = shift();
        print $msg;
    }

}

sub basename($) {
 my $file = shift;
 $file =~ s!^(?:.*/)?(.+?)(?:\.[^.]*)?$!$1!;
 return $file;
}

sub dirname($) {my $file = shift; $file =~ s!/?[^/]*/*$!!; return $file; }

&print_debug("MusicFS 0.1\n");

my $basedir = shift(@ARGV);
my $mountpoint = shift(@ARGV);
$debug = shift(@ARGV);
if (!defined($debug))
{
    $debug = "";
}

&print_debug("Reading Basedirectory...\n");

my @basedir_content_mp3;
my @basedir_content_ogg;

open(BASEDIR_MP3, "find $basedir -follow -name *.mp3|");
open(BASEDIR_OGG, "find $basedir -follow -name *.ogg|");

while(<BASEDIR_MP3>)
{
    chop();
    push(@basedir_content_mp3, $_);    
}

while(<BASEDIR_OGG>)
{
    chop();
    push(@basedir_content_ogg, $_);    
}

close(BASEDIR_MP3);
close(BASEDIR_OGG);

my $genres = {};
my $years = {};
my $artists = {};

my $count_files = 0;
my $count_genres = 0;
my $count_years = 0;
my $count_artists = 0;

&print_debug("==PROCESSING MPEG1 Layer3 Files==\n");

foreach my $file (@basedir_content_mp3)
{
    if($file eq ".." || $file eq ".")
    {
        next;
    }
    
    &print_debug("==ADDING==>");
    my $filetag = MP3::Tag->new($file);
    if(!defined $filetag)
    {
        &print_debug("No readable Tag. Skipping file!\n");
        next;
    }

    $filetag->get_tags();
    if(exists $filetag->{ID3v1})
    {
        my $genre = $filetag->{ID3v1}->genre;
        my $artist = $filetag->{ID3v1}->artist;
        my $title = $filetag->{ID3v1}->title;
        my $year = $filetag->{ID3v1}->year;
        my $album = $filetag->{ID3v1}->album;
        my $track = $filetag->{ID3v1}->track;
        my $hasAlbumArt = 0;
        my $albumArtData = "";
        
        if (exists $filetag->{ID3v2})
        {
            $genre = $filetag->{ID3v2}->genre if defined $filetag->{ID3v2}->genre;
            $artist = $filetag->{ID3v2}->artist if defined $filetag->{ID3v2}->artist;
            $title = $filetag->{ID3v2}->title if defined $filetag->{ID3v2}->title;
            $year = $filetag->{ID3v2}->year if defined $filetag->{ID3v2}->year;
            $album = $filetag->{ID3v2}->album if defined $filetag->{ID3v2}->album;
            $track = $filetag->{ID3v2}->track if defined $filetag->{ID3v2}->track;
            
            #print_debug(" ID3v2 APIC: ". $filetag->{ID3v2}->get_frame("APIC") . "\n" );
        
            my $apicTagInfo = {};
            my $apicTagDescription = "";
            ( $apicTagInfo, $apicTagDescription ) = $filetag->{ID3v2}->get_frame("APIC");
            
            if (defined $apicTagDescription && $apicTagDescription =~ /Attached Picture/igo)
            {
                print_debug(" ID3v2 APIC Data: " . $apicTagInfo . "\n");
                #         ( { "Description" => "Flood", 
                #             "MIME Type" => "/image/jpeg", 
                #             "Picture Type" => "Cover (front)",
                #             "_Data" => "..data of jpeg picture (binary).."
                #            },
                #"Attached Picture");
                #print "File \"$artist - $title.mp3\" has album art with MIME Type \"" . $apicTagInfo->{"MIME type"} . "\"!\n";
                
                
                $albumArtData = $apicTagInfo->{"_Data"};
                $hasAlbumArt = 1;
                
                #foreach my $key ( keys %{$apicTagInfo} )
                #{
                #  print "APIC key: $key\n";
                #}
            }
        }
        
        &print_debug("$artist - $title\n");

        $count_files++;
        
        #Genre  
        if($genre eq "") { $genre = "Unknown"; };
    
        if ($genre eq "AlternRock") { $genre = "Alternative"; }
        
        if(!exists $filesystem->{root}->{content}->{Genre}->{content}->{$genre})
        {
            $filesystem->{root}->{content}->{Genre}->{content}->{$genre}->{type} = 'dir';
            $count_genres++;
        }
        
        
        $filesystem->{root}->{content}->{Genre}->{content}->{$genre}->{content}->{"$artist - $title.mp3"}->{type} = 'file';
        $filesystem->{root}->{content}->{Genre}->{content}->{$genre}->{content}->{"$artist - $title.mp3"}->{content} = $file;

        #Year
        if($year eq "") { $year = "Unknown"; };
        
        if(!exists $filesystem->{root}->{content}->{Year}->{content}->{$year})
        {
            $filesystem->{root}->{content}->{Year}->{content}->{$year}->{type} = 'dir';
            $count_years++;
        }
        $filesystem->{root}->{content}->{Year}->{content}->{$year}->{content}->{"$artist - $title.mp3"}->{type} = 'file';
        $filesystem->{root}->{content}->{Year}->{content}->{$year}->{content}->{"$artist - $title.mp3"}->{content} = $file;
        
        #####Artist######
        if($album eq "") { $album = "Unknown"; };
        if($track eq "") { $track = "NA"; };
        
        if(!exists $filesystem->{root}->{content}->{Artist}->{content}->{$artist})
        {
            $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{type} = 'dir';
            $count_artists++;
        }
        # Create Album folder
        if(!exists $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album})
        {
            $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{type} = 'dir';
            $filesystem->{root}->{content}->{Album}->{content}->{$album}->{type} = 'dir';
        }
        
        $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"$track - $title.mp3"}->{type} = 'file';
        $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"$track - $title.mp3"}->{content} = $file;
        
        $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"$track - $title.mp3"}->{type} = 'file';
        $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"$track - $title.mp3"}->{content} = $file;
        
        # Album art
        if ($hasAlbumArt)
        {
            my $albumArtFileName = "/tmp/" . basename($file) . ".jpg";
            
            if (!exists $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"folder.jpg"})
            {
                $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"folder.jpg"}->{type} = 'file';
                $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"folder.jpg"}->{content} = $albumArtData;
            }
            
            if (!exists $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"folder.jpg"})
            {
                $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"folder.jpg"}->{type} = 'file';
                $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"folder.jpg"}->{content} = $albumArtData;
            }
            
        }
    }
    else
    {   
        &print_debug("No IDv1 Tag. Skipping file!\n");
    }
    $filesystem->{root}->{content}->{fsinfo}->{content} = "MusicFS Stats: Got $count_files Files in $count_genres genres from $count_artists Artists\n";    
}


&print_debug("==PROCESSING OGG Vorbis Files==\n");
foreach my $file (@basedir_content_ogg)
{
    if($file eq ".." || $file eq ".")
    {
        next;
    }
    
    &print_debug("==ADDING==>");
    my $filetag = Ogg::Vorbis::Header->new($file);
    if(!defined $filetag)
    {
        &print_debug("No readable Tag. Skipping file!\n");
        next;
    }

    my @genre_a = $filetag->comment("GENRE");
    my @artist_a = $filetag->comment("ARTIST");
    my @title_a = $filetag->comment("TITLE");
    my @year_a = $filetag->comment("YEAR");
    my @album_a = $filetag->comment("ALBUM");
    my @track_a = $filetag->comment("TRACKNUMBER");
    
    my $genre = $genre_a[0];
    my $artist = $artist_a[0];
    my $title = $title_a[0];
    my $year = $year_a[0];
    my $album = $album_a[0];
    my $track = $track_a[0];
                    
    
    &print_debug("$artist - $title\n");

    $count_files++;
    
    #Genre  
    if(!defined $genre) { $genre = "unknown"; };
    if(!defined $year) { $year = "unknown"; };
    
    if ($genre eq "AlternRock") { $genre = "Alternative"; }

    
    if(!exists $filesystem->{root}->{content}->{Genre}->{content}->{$genre})
    {
        $filesystem->{root}->{content}->{Genre}->{content}->{$genre}->{type} = 'dir';
        $count_genres++;
    }
    $filesystem->{root}->{content}->{Genre}->{content}->{$genre}->{content}->{"$artist - $title.ogg"}->{type} = 'file';
    $filesystem->{root}->{content}->{Genre}->{content}->{$genre}->{content}->{"$artist - $title.ogg"}->{content} = $file;

    #Year
    if($year eq "") { $year = "unknown"; };
    
    if(!exists $filesystem->{root}->{content}->{Year}->{content}->{$year})
    {
        $filesystem->{root}->{content}->{Year}->{content}->{$year}->{type} = 'dir';
        $count_years++;
    }
    $filesystem->{root}->{content}->{Year}->{content}->{$year}->{content}->{"$artist - $title.ogg"}->{type} = 'file';
    $filesystem->{root}->{content}->{Year}->{content}->{$year}->{content}->{"$artist - $title.ogg"}->{content} = $file;
    
    #####Artist######
    if($album eq "") { $album = "unknown"; };
    if($track eq "") { $track = "NA"; };
    
    if(!exists $filesystem->{root}->{content}->{Artist}->{content}->{$artist})
    {
        $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{type} = 'dir';
        $count_artists++;
    }
    # Create Album folder
    if(!exists $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album})
    {
        $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{type} = 'dir';
        $filesystem->{root}->{content}->{Album}->{content}->{$album}->{type} = 'dir';
    }
    
    $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"$track - $title.ogg"}->{type} = 'file';
    $filesystem->{root}->{content}->{Artist}->{content}->{$artist}->{content}->{$album}->{content}->{"$track - $title.ogg"}->{content} = $file;
    
    $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"$track - $title.ogg"}->{type} = 'file';
    $filesystem->{root}->{content}->{Album}->{content}->{$album}->{content}->{"$track - $title.ogg"}->{content} = $file;

    $filesystem->{root}->{content}->{fsinfo}->{content} = "MusicFS Stats: Got $count_files Files in $count_genres genres from $count_artists Artists\n";    
}








&print_debug("==READY==>" . $filesystem->{root}->{content}->{fsinfo}->{content});

Fuse::main(
    mountpoint  => $mountpoint,
    mountopts => "allow_other",
    getdir      => \&my_getdir,
    getattr     => \&my_getattr,
    read        => \&my_read,
    debug => 0
);



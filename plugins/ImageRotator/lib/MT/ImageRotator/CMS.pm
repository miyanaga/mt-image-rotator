package MT::ImageRotator::CMS;

use strict;
use MT::FileMgr;
use MT::Image;

sub _rotate_image {
    my ( $app, $asset, $deg ) = @_;

    my $blog = $asset->blog;
    my $fmgr = $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
    my $data = $fmgr->get_data( $asset->file_path, 'upload' );

    my $img = MT::Image->new( Data => $data, Type => $asset->file_ext );

    my ( $blob, $width, $height ) = $img->rotate( Degrees => $deg );
    $fmgr->put_data( $blob, $asset->file_path, 'upload' );
    $asset->image_width($width);
    $asset->image_height($height);

    $asset->save;
}

sub _append_rotated_message {
    my ( $cb, $app, $param, $tmpl ) = @_;

    my $msg = $tmpl->createElement( 'SetVarBlock', {
        name => 'system_msg',
    });
    $msg->innerHTML(q{
        <__trans_section component="ImageRotator">
        <mt:if name="not_image">
            <mtapp:statusmsg id="not-image" class="error" can_close="1">
            <__trans phrase="Asset is not an image.">
            </mtapp:statusmsg>
        </mt:if>
        <mt:if name="rotated">
            <mtapp:statusmsg id="rotated" class="success" can_close="1">
                <mt:if name="rs_bulk">
                    <__trans phrase="BULK_ROTATED_IMAGES" params="<mt:var name='done' escape='html'>">
                <mt:else>
                <__trans phrase="Image rotated.">
                </mt:if>
            </mtapp:statusmsg>
        </mt:if>
        </__trans_section>
    });

    $param->{rotated} = $app->param('rotated');
    $param->{done} = $app->param('done');

    my ( $header_include ) = grep {
        $_->getAttribute('name') =~ m!include/header!;
    } @{ $tmpl->getElementsByTagName('include') };

    $tmpl->insertBefore( $msg, $header_include );

    $header_include;
}

sub template_param_list_common {
    my ( $cb, $app, $param, $tmpl ) = @_;

    # Check type
    return 1 if $param->{object_type} ne 'asset';

    # Check permission
    return 1 if $app->blog && !$app->can_do('rotate_image');

    $param->{rs_bulk} = 1;
    my $header_include = _append_rotated_message(@_);

    1;
}

sub template_param_edit_asset {
    my ( $cb, $app, $param, $tmpl ) = @_;

    # Check Type
    my $type = $param->{asset_type} || $param->{class} || '';
    return 1 if $type ne 'image';

    # Check permission
    return 1 unless $app->can_do('rotate_image');

    my $header_include = _append_rotated_message(@_);

    my $widget = $tmpl->createElement( 'SetVarBlock', {
        name => 'related_content',
        append => 1,
    });
    $widget->innerHTML(q{
        <__trans_section component="ImageRotator">
        <mtapp:widget id="rs-rotate" label="<__trans phrase='Image Rotation'>">
            <ul>
                <li><a href="<mt:var name='rotate_90_url'>"><__trans phrase="Rotate 90 Deg. Clockwise"></a></li>
                <li><a href="<mt:var name='rotate_180_url'>"><__trans phrase="Rotate 180 Deg."></a></li>
                <li><a href="<mt:var name='rotate_270_url'>"><__trans phrase="Rotate 90 Deg. Counter Clockwise"></a></li>
            </ul>
        </mtapp:widget>
        </__trans_section>
    });

    foreach my $deg ( qw/90 180 270/ ) {
        my %hash = $app->param_hash;
        delete $hash{__mode};
        $param->{"rotate_${deg}_url"} = $app->uri(
            mode => 'single_rotate_image',
            args => { %hash, deg => $deg },
        );
    }

    $tmpl->insertBefore( $widget, $header_include );

    1;
}

sub single_rotate_image {
    my ( $app ) = @_;
    my %hash = $app->param_hash;
    delete $hash{__mode};

    # Check permission
    return $app->permission_denied
        unless $app->can_do('rotate_image');

    my $id = $app->param('id');
    my $asset = MT->model('asset')->load($id);

    # Check type
    return $app->redirect( $app->uri(
        mode => 'view',
        args => { %hash, no_image => 1 },
    )) unless $asset->class eq 'image';

    # Roate image
    my $deg = $app->param('deg') || 90;
    _rotate_image( $app, $asset, $deg );

    $app->redirect( $app->uri(
        mode    => 'view',
        args    => { %hash, rotated => 1 },
    ));
}

sub bulk_rotate_image {
    my ( $app ) = @_;
    my $author = $app->user 
        or return $app->permission_denied;

    # Degree
    my $action = $app->param('action_name') || 'rotate_90';
    my ( $deg ) = $action =~ m!rotate_(\d+)!;
    $deg ||= 90;

    # Ids
    my @ids = $app->param('id');

    # Loop ids
    my $done;
    foreach my $id ( @ids ) {

        # Check permission
        my $asset = MT->model('asset')->load($id) or next;

        # Check type
        next if $asset->class ne 'image';

        if ( my $blog = $asset->blog ) {

            my $perms = $author->permissions($blog->id) or next;
            next unless $perms->can_do('rotate_image');

        } else {

            # System scope image(userpic)
            next unless $author->is_superuser;
        }

        # Rotate image
        _rotate_image( $app, $asset, $deg );

        $done++;
    }

    $app->add_return_arg( 'rotated' => 1, 'done' => $done );
    $app->call_return;
}

1;

import UIKit
/// Direct thumbnail dragging keeps a single-resource preview and also handles a
/// quick mouse release that does not start a system drag session.
final class ResourceThumbnailView:UIImageView {
 var onTap:(()->Void)?,onDrop:((CGPoint,UIWindow)->Void)?
 private var start:CGPoint?,ghost:UIImageView?
 override init(frame:CGRect){super.init(frame:frame);isUserInteractionEnabled=true;contentMode = .scaleAspectFit;layer.cornerRadius=6;clipsToBounds=true;accessibilityLabel="拖动这个缩略图到 iOS 手机"}
 required init?(coder:NSCoder){fatalError()}
 override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?){guard let window=window,let t=touches.first else{return};start=t.location(in:window)}
 override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?){guard let window=window,let start=start,let p=touches.first?.location(in:window),hypot(p.x-start.x,p.y-start.y)>6 else{return};if ghost==nil{let g=UIImageView(image:image);g.contentMode = .scaleAspectFit;g.frame=CGRect(x:0,y:0,width:112,height:90);g.layer.shadowOpacity=0.15;g.layer.shadowRadius=4;g.isUserInteractionEnabled=false;window.addSubview(g);ghost=g};ghost?.center=p}
 override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){defer{start=nil;ghost?.removeFromSuperview();ghost=nil};guard let window=window,let start=start,let p=touches.first?.location(in:window) else{return};if hypot(p.x-start.x,p.y-start.y)>10{onDrop?(p,window)}else{onTap?()}}
 override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){start=nil;ghost?.removeFromSuperview();ghost=nil}
}
final class ResourceLayerCell:UITableViewCell {
 var indent:CGFloat=0
 let thumb=ResourceThumbnailView(frame:.zero),title=UILabel(),subtitle=UILabel(),expand=UIButton(type:.system)
 override init(style:UITableViewCell.CellStyle,reuseIdentifier:String?){super.init(style:style,reuseIdentifier:reuseIdentifier);[thumb,title,subtitle,expand].forEach{contentView.addSubview($0)};title.font = .systemFont(ofSize:13,weight:.medium);title.numberOfLines=2;subtitle.font = .systemFont(ofSize:11);subtitle.textColor=UIColor(studioHex:"#526273");expand.setTitle("展开 ›",for:.normal);expand.titleLabel?.font = .systemFont(ofSize:12);selectionStyle = .none}
 required init?(coder:NSCoder){fatalError()}
 override func layoutSubviews(){super.layoutSubviews();let w=contentView.bounds.width;let offset=min(indent,60);thumb.frame=CGRect(x:6+offset,y:8,width:72-offset/2,height:60);let trailing:CGFloat=expand.isHidden ? 8:54;title.frame=CGRect(x:88+offset/2,y:10,width:max(30,w-88-trailing-offset/2),height:34);subtitle.frame=CGRect(x:88+offset/2,y:46,width:max(30,w-96-offset/2),height:18);expand.frame=CGRect(x:w-54,y:12,width:50,height:30)}
}

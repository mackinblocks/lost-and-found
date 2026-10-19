import hashlib
import os
import re
from flask import Flask, render_template, request, redirect, url_for, flash, session, g
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from datetime import datetime
from functools import wraps

app = Flask(__name__)
# Read the secret key from an environment variable when the site is hosted for real;
# the fallback is only for running it on your own computer.
app.secret_key = os.environ.get("SECRET_KEY", "uc-lost-and-found-secret")
# "Lax" stops other websites from submitting our forms with a logged-in user's cookie.
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

# --- Database ---
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///lostfound.db"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# --- File Uploads ---
UPLOAD_FOLDER = os.path.join("static", "uploads")
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# --- Usernames & Messages ---
# 3-30 characters: letters, numbers, underscore, dot or dash (no spaces, so names work in links).
USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{3,30}$")
MAX_MESSAGE_LENGTH = 2000

db = SQLAlchemy(app)


# --- Models ---
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    posts = db.relationship("Post", backref="author", lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


class Post(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(10), nullable=False)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=False)
    location = db.Column(db.String(200), nullable=False)
    contact = db.Column(db.String(200), nullable=False)
    date = db.Column(db.String(20), nullable=False)
    image_filename = db.Column(db.String(300), nullable=True)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    resolved = db.Column(db.Boolean, default=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)


class Message(db.Model):
    """A private message between two users, optionally about a specific post."""
    id = db.Column(db.Integer, primary_key=True)
    sender_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    recipient_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    post_id = db.Column(db.Integer, db.ForeignKey("post.id"), nullable=True)
    body = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    read = db.Column(db.Boolean, default=False)

    sender = db.relationship("User", foreign_keys=[sender_id])
    recipient = db.relationship("User", foreign_keys=[recipient_id])
    post = db.relationship("Post")


# --- Helpers ---
def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def current_user():
    """The logged-in User, or None. Looked up once per request and reused."""
    if "current_user" not in g:
        user_id = session.get("user_id")
        g.current_user = db.session.get(User, user_id) if user_id else None
    return g.current_user


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if current_user() is None:
            # Covers both "not logged in" and "logged in as an account that no longer exists".
            session.clear()
            flash("Please log in to continue.", "warning")
            return redirect(url_for("login", next=request.full_path.rstrip("?")))
        return f(*args, **kwargs)
    return decorated


def safe_next_url(target):
    """Only allow redirects to pages on this site (stops links that bounce users to other sites)."""
    if target and target.startswith("/") and not target.startswith("//") and "\\" not in target:
        return target
    return None


def find_user(username):
    return User.query.filter_by(username=username).first_or_404()


# Clearly different colors that all keep white letters readable.
AVATAR_COLORS = [
    "#1565c0",  # blue
    "#2e7d32",  # green
    "#6a1b9a",  # purple
    "#00838f",  # teal
    "#ad1457",  # pink
    "#bf360c",  # burnt orange
    "#283593",  # indigo
    "#4e342e",  # brown
    "#00695c",  # dark green-teal
    "#37474f",  # slate
    "#8e24aa",  # violet
    "#9e2a2b",  # brick red
]


def avatar_color(username):
    """Give every username its own consistent color, so people are easy to recognize."""
    digest = hashlib.md5(username.lower().encode("utf-8")).digest()
    return AVATAR_COLORS[digest[0] % len(AVATAR_COLORS)]


def unread_message_count():
    user = current_user()
    if user is None:
        return 0
    return Message.query.filter_by(recipient_id=user.id, read=False).count()


@app.template_filter("timeago")
def timeago(value):
    """Turn a timestamp into '5 min ago', '3 hr ago', 'Oct 12'."""
    if value is None:
        return ""
    seconds = int((datetime.utcnow() - value).total_seconds())
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{seconds // 60} min ago"
    if seconds < 86400:
        return f"{seconds // 3600} hr ago"
    if seconds < 7 * 86400:
        days = seconds // 86400
        return f"{days} day{'s' if days != 1 else ''} ago"
    return value.strftime("%b %d").replace(" 0", " ")


app.jinja_env.globals["current_user"] = current_user
app.jinja_env.globals["avatar_color"] = avatar_color
app.jinja_env.globals["unread_message_count"] = unread_message_count


# --- Routes ---
@app.route("/")
def index():
    filter_type = request.args.get("type", "all")
    query = request.args.get("q", "").lower()

    posts = Post.query
    if filter_type in ("lost", "found"):
        posts = posts.filter_by(type=filter_type)
    if query:
        posts = posts.filter(
            db.or_(
                Post.title.ilike(f"%{query}%"),
                Post.description.ilike(f"%{query}%"),
                Post.location.ilike(f"%{query}%"),
            )
        )
    posts = posts.order_by(Post.timestamp.desc()).all()
    return render_template("index.html", posts=posts, filter_type=filter_type, query=query)


@app.route("/register", methods=["GET", "POST"])
def register():
    next_url = safe_next_url(request.values.get("next"))
    if request.method == "POST":
        username = request.form["username"].strip()
        email = request.form["email"].strip()
        password = request.form["password"]

        if not USERNAME_PATTERN.match(username):
            flash("Usernames need 3-30 characters: letters, numbers, _ . or - (no spaces).", "danger")
            return redirect(url_for("register", next=next_url))
        # Case-insensitive check, so nobody can pose as "BearcatJoe" when "bearcatjoe" exists.
        if User.query.filter(db.func.lower(User.username) == username.lower()).first():
            flash("Username already taken.", "danger")
            return redirect(url_for("register", next=next_url))
        if User.query.filter(db.func.lower(User.email) == email.lower()).first():
            flash("Email already registered.", "danger")
            return redirect(url_for("register", next=next_url))

        user = User(username=username, email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        session["user_id"] = user.id
        flash(f"Account created! Welcome to Bearcats Lost & Found, {user.username}.", "success")
        return redirect(next_url or url_for("index"))
    return render_template("register.html", next_url=next_url)


@app.route("/login", methods=["GET", "POST"])
def login():
    next_url = safe_next_url(request.values.get("next"))
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            session.clear()
            session["user_id"] = user.id
            flash(f"Welcome back, {user.username}!", "success")
            return redirect(next_url or url_for("index"))
        flash("Invalid username or password.", "danger")
    return render_template("login.html", next_url=next_url)


@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "info")
    return redirect(url_for("index"))


@app.route("/user/<username>")
def profile(username):
    user = find_user(username)
    posts = Post.query.filter_by(user_id=user.id).order_by(Post.timestamp.desc()).all()
    return render_template("profile.html", user=user, posts=posts)


@app.route("/post/new", methods=["GET", "POST"])
@login_required
def new_post():
    if request.method == "POST":
        image_filename = None
        file = request.files.get("image")
        if file and file.filename and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            unique_name = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S')}_{filename}"
            file.save(os.path.join(app.config["UPLOAD_FOLDER"], unique_name))
            image_filename = unique_name

        post = Post(
            type=request.form["type"],
            title=request.form["title"],
            description=request.form["description"],
            location=request.form["location"],
            contact=request.form["contact"],
            date=request.form["date"],
            image_filename=image_filename,
            user_id=current_user().id,
        )
        db.session.add(post)
        db.session.commit()
        flash("Post submitted!", "success")
        return redirect(url_for("index"))
    return render_template("new_post.html")


@app.route("/post/<int:post_id>")
def view_post(post_id):
    post = db.get_or_404(Post, post_id)
    return render_template("post.html", post=post)


@app.route("/post/<int:post_id>/delete", methods=["POST"])
@login_required
def delete_post(post_id):
    post = db.get_or_404(Post, post_id)
    if post.user_id != current_user().id:
        flash("You can only delete your own posts.", "danger")
        return redirect(url_for("view_post", post_id=post_id))
    if post.image_filename:
        try:
            os.remove(os.path.join(app.config["UPLOAD_FOLDER"], post.image_filename))
        except FileNotFoundError:
            pass
    # Keep the conversation history, just unlink it from the deleted post.
    Message.query.filter_by(post_id=post.id).update({"post_id": None})
    db.session.delete(post)
    db.session.commit()
    flash("Post deleted.", "info")
    return redirect(url_for("index"))


@app.route("/post/<int:post_id>/resolve", methods=["POST"])
@login_required
def resolve_post(post_id):
    post = db.get_or_404(Post, post_id)
    if post.user_id != current_user().id:
        flash("You can only resolve your own posts.", "danger")
        return redirect(url_for("view_post", post_id=post_id))
    post.resolved = not post.resolved
    db.session.commit()
    return redirect(url_for("view_post", post_id=post_id))


# --- Messaging ---
@app.route("/messages")
@login_required
def inbox():
    """List every conversation the logged-in user is part of, newest first."""
    me = current_user()
    messages = (
        Message.query
        .filter(db.or_(Message.sender_id == me.id, Message.recipient_id == me.id))
        .order_by(Message.timestamp.desc())
        .all()
    )
    conversations = {}
    for message in messages:
        other = message.recipient if message.sender_id == me.id else message.sender
        if other is None:
            continue
        convo = conversations.setdefault(other.id, {"other": other, "last": message, "unread": 0})
        if message.recipient_id == me.id and not message.read:
            convo["unread"] += 1
    return render_template("messages.html", conversations=list(conversations.values()))


@app.route("/messages/<username>", methods=["GET", "POST"])
@login_required
def conversation(username):
    """Private conversation between the logged-in user and one other user."""
    me = current_user()
    other = find_user(username)
    if other.id == me.id:
        flash("You can't message yourself.", "warning")
        return redirect(url_for("inbox"))

    if request.method == "POST":
        body = request.form.get("body", "").strip()
        post_id = request.form.get("post_id", type=int)
        post = db.session.get(Post, post_id) if post_id else None
        if not body:
            flash("Type a message before sending.", "warning")
        elif len(body) > MAX_MESSAGE_LENGTH:
            flash(f"Messages can be at most {MAX_MESSAGE_LENGTH} characters.", "danger")
        else:
            db.session.add(Message(
                sender_id=me.id,
                recipient_id=other.id,
                post_id=post.id if post else None,
                body=body,
            ))
            db.session.commit()
        return redirect(url_for("conversation", username=other.username))

    # Only messages between these two people: nobody else can read this conversation.
    thread = (
        Message.query
        .filter(db.or_(
            db.and_(Message.sender_id == me.id, Message.recipient_id == other.id),
            db.and_(Message.sender_id == other.id, Message.recipient_id == me.id),
        ))
        .order_by(Message.timestamp.asc())
        .all()
    )
    # Opening the conversation marks their messages to you as read.
    Message.query.filter_by(sender_id=other.id, recipient_id=me.id, read=False).update({"read": True})
    db.session.commit()

    # "Message the poster" links pass ?post=<id> so the first message is tied to that post.
    about_post = None
    about_id = request.args.get("post", type=int)
    if about_id:
        about_post = db.session.get(Post, about_id)

    return render_template(
        "conversation.html",
        other=other,
        thread=thread,
        about_post=about_post,
        max_length=MAX_MESSAGE_LENGTH,
    )


if __name__ == "__main__":
    with app.app_context():
        db.create_all()
    app.run(host="0.0.0.0", debug=True)

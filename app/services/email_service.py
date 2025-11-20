import smtplib
import random
import string
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session
from app.config import settings
from app.models.password_reset import PasswordResetToken
from app.models.user import User


def generate_otp(length: int = 6) -> str:
    """Generate a random OTP code"""
    return ''.join(random.choices(string.digits, k=length))


def send_email(to_email: str, subject: str, body: str) -> bool:
    """Send email using SMTP"""
    try:
        # Create message
        msg = MIMEMultipart()
        msg['From'] = f"{settings.email_sender_name} <{settings.email_sender_address}>"
        msg['To'] = to_email
        msg['Subject'] = subject

        # Add body to email
        msg.attach(MIMEText(body, 'html'))

        # Create SMTP session
        server = smtplib.SMTP(settings.email_smtp_server, settings.email_smtp_port)
        server.starttls()  # Enable security
        server.login(settings.email_smtp_username, settings.email_smtp_password)

        # Send email
        text = msg.as_string()
        server.sendmail(settings.email_sender_address, to_email, text)
        server.quit()

        return True
    except Exception as e:
        print(f"Error sending email: {e}")
        return False


def send_password_reset_otp(db: Session, user: User) -> Optional[str]:
    """Send password reset OTP to user's email"""
    # Generate OTP
    otp = generate_otp()

    # Create reset token in database
    reset_token = PasswordResetToken(
        user_id=user.id,
        token=otp,
        expires_at=datetime.utcnow() + timedelta(minutes=15)  # 15 minutes expiry
    )

    db.add(reset_token)
    db.commit()

    # Email template
    subject = "Password Reset OTP - Sentinel Security"
    body = f"""
    <html>
    <body>
        <h2>Password Reset Request</h2>
        <p>Hello {user.username},</p>
        <p>You have requested to reset your password for your Sentinel Security account.</p>

        <div style="background: #f5f5f5; padding: 20px; margin: 20px 0; border-radius: 8px; text-align: center;">
            <h3>Your OTP Code:</h3>
            <h1 style="color: #007bff; letter-spacing: 4px; margin: 10px 0;">{otp}</h1>
            <p><strong>This code will expire in 15 minutes.</strong></p>
        </div>

        <p>If you didn't request this password reset, please ignore this email.</p>

        <p>Best regards,<br>
        The Sentinel Security Team</p>

        <hr>
        <p style="font-size: 12px; color: #666;">
            This is an automated email. Please do not reply to this message.
        </p>
    </body>
    </html>
    """

    # Send email
    if send_email(user.email, subject, body):
        return otp
    else:
        # If email failed, delete the token
        db.delete(reset_token)
        db.commit()
        return None


def verify_password_reset_otp(db: Session, email: str, otp: str) -> Optional[User]:
    """Verify password reset OTP and return user if valid"""
    user = db.query(User).filter(User.email == email).first()
    if not user:
        return None

    # Find valid token
    token = db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.token == otp,
        PasswordResetToken.is_used == False,
        PasswordResetToken.expires_at > datetime.utcnow()
    ).first()

    if token:
        # Mark token as used
        token.is_used = True
        db.commit()
        return user

    return None


def cleanup_expired_tokens(db: Session):
    """Clean up expired password reset tokens"""
    expired_tokens = db.query(PasswordResetToken).filter(
        PasswordResetToken.expires_at < datetime.utcnow()
    ).all()

    for token in expired_tokens:
        db.delete(token)

    db.commit()
    return len(expired_tokens)
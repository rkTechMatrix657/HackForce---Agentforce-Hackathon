import { LightningElement } from 'lwc';
import registerCustomer from '@salesforce/apex/HFSelfRegistrationController.registerCustomer';

export default class HfSelfRegister extends LightningElement {
    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    password = '';
    confirmPassword = '';

    isSubmitting = false;
    errorMessage = '';
    successMessage = '';

    get isSuccess() {
        return !!this.successMessage;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get isDisabled() {
        return this.isSubmitting || this.isSuccess;
    }

    handleFirstName(event) {
        this.firstName = event.target.value;
    }

    handleLastName(event) {
        this.lastName = event.target.value;
    }

    handleEmail(event) {
        this.email = event.target.value;
    }

    handlePhone(event) {
        this.phone = event.target.value;
    }

    handlePassword(event) {
        this.password = event.target.value;
    }

    handleConfirmPassword(event) {
        this.confirmPassword = event.target.value;
    }

    async handleSubmit(event) {
        event.preventDefault();
        this.errorMessage = '';

        if (!this.firstName || !this.lastName || !this.email || !this.password) {
            this.errorMessage = 'Please fill in all required fields.';
            return;
        }
        if (this.password.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.';
            return;
        }
        if (this.password !== this.confirmPassword) {
            this.errorMessage = 'Passwords do not match.';
            return;
        }

        this.isSubmitting = true;
        try {
            await registerCustomer({
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                phone: this.phone,
                password: this.password
            });
            this.successMessage = 'Account created! Redirecting you to login…';
            setTimeout(() => {
                window.location.href = '/HFFinance/s/login';
            }, 1800);
        } catch (error) {
            this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong. Please try again.';
        } finally {
            this.isSubmitting = false;
        }
    }
}